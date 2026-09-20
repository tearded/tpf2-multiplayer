"""Offline checks for quick line-editor clicks (inject.lua LUPDATE merge, lines.lua CM.lineBaseFor), on Lua 5.2.

A quick click in the line editor is built from the list the EDITOR last saw. With strict
line updates an earlier click can apply between the click and the moment the Lua reads
it, so diffing the click against the line's current list read "stop 1 removed, stop 3
added" for a click that only added stop 3 -- the merge deleted stop 1 (b:6, 2026-09-12:
three quick stations applied as 1, 2, 2 stops on every instance).

This loads the real inject.lua and lines.lua with stub CM/api and replays that session's
shape: each click is a decoded LUPDATE built from the editor's (possibly stale) list, and
an update "applies" the way execLine records it (the list before and after it).
  - click 2 while click 1 waits: both stops
  - click 3 built from the EMPTY list after click 1 applied: all three stops, none lost
  - click 4 built from the one-stop list: four stops
  - removing the stop just added (nothing waiting): a removal, not a no-op
  - A BURST OF 14 (2026-09-16): the engine's confirmations lag the whole burst, the editor
    never refreshes past the first stop, and every click is built from that one-stop list.
    The bases used to be kept 12 deep and 8 game units back, so from the 8th click on the
    true base was gone and the merge shipped a list the player never made. Bases are now
    kept until the line's edits drain (nothing queued, nothing unconfirmed); once they do,
    only the last update's before/after lists remain.

  - A RE-SET OF THE STOP JUST ADDED (2026-09-19): the editor keeps showing the list IT
    built, so a click that changes the platform (or wait time) of a stop whose add is
    still on its way is built from the shipped list, not from the entity. Based on the
    entity it read "B1 added" and the merge put B1 next to the B0 still on its way -- the
    line held the same stop twice and every later click carried the pair along (line
    121756: one stop three times). The lists this editor sent come first now; a removal
    of a stop still on its way is a removal too, not a no-op against the entity.

    python tools/line_rapid_edit_test.py
    TPF2_LINES_LUA=<path> python tools/line_rapid_edit_test.py   # another lines.lua (an older build)
"""
import os
import sys
import tempfile

import lupa.lua52 as lupa

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MP = os.path.join(REPO, "mod", "mp_lockstep_1", "res", "scripts", "mp")
LINES_LUA = os.environ.get("TPF2_LINES_LUA") or os.path.join(MP, "lines.lua")
LID = 108664
POS = {107158 + 3 * i: 10 * (i + 1) for i in range(16)}   # station group -> x

fails = []


def check(name, cond, extra=""):
    print(("ok   " if cond else "FAIL ") + name + (f"  ({extra})" if extra else ""))
    if not cond:
        fails.append(name)


def stop_str(sg):
    return f"{POS[sg]:.2f},0.00,0,0,0,0,180"


def click_line(sgs):
    parts = ["LUPDATE", str(LID), "180", str(len(sgs))]
    for sg in sgs:
        parts += [str(sg), "0", "0", "0", "0", "180", "0"]
    return " ".join(parts)


# a stop with a platform (station index) and a minimum wait: (sg, station, minWait)
def stop_str2(sg, st=0, mn=0):
    return f"{POS[sg]:.2f},0.00,{st},0,0,{mn},180"


def click_line2(stops):
    parts = ["LUPDATE", str(LID), "180", str(len(stops))]
    for sg, st, mn in stops:
        parts += [str(sg), str(st), "0", "0", str(mn), "180", "0"]
    return " ".join(parts)


def runtime(inject_path):
    L = lupa.LuaRuntime(unpack_returned_tuples=True)
    L.globals().package.path = os.path.join(REPO, "mod/mp_lockstep_1/res/scripts/?.lua").replace("\\", "/") + ";" + L.globals().package.path
    g = L.globals()
    g.INJECT_SRC = open(os.path.join(MP, "inject.lua"), encoding="utf-8").read()
    g.LINES_SRC = open(LINES_LUA, encoding="utf-8").read()
    g.INJECT = inject_path.replace("\\", "/")
    g.STATION_POS = " ".join("%d=%d" % kv for kv in POS.items())
    return L.execute(r'''
local logs, sched = {}, {}
local function sink()
  return setmetatable({}, { __index = function() return sink() end, __call = function() return nil end })
end
api = setmetatable({}, { __index = function() return sink() end })
game = setmetatable({}, { __index = function() return sink() end })
local K = setmetatable({ INSTANCE = "b", INJECT_FILE = INJECT, BASE = "",
                         STRICT_OPS = { LCREATE = true, LUPDATE = true, LDELETE = true } },
  { __index = function() return nil end })
local CM = { peerSeen = true, injectOffset = 0, seqNo = 6, ticks = 0, queue = {} }
local now = 100
function CM.gameTime() return now end
function CM.stepOf(t) return math.floor((t or 0) / 0.2 + 0.5) end
function CM.scheduleLocal(op, args)
  if CM.resyncHold then return end   -- as the real one: nothing is queued under a resync hold
  CM.seqNo = CM.seqNo + 1
  args.op, args.seq, args.at = op, CM.seqNo, now + 0.8
  sched[#sched + 1] = args
  CM.queue[#CM.queue + 1] = args
end
function CM.escName(s) return s end
function CM.unescName(s) return s end
function CM.readFrom(path, offset)
  local f = io.open(path, "rb")
  if not f then return nil, offset end
  local size = f:seek("end")
  if offset >= size then f:close(); return nil, offset end
  f:seek("set", offset)
  local data = f:read("*a") or ""
  f:close()
  local last = #data
  while last > 0 and data:byte(last) ~= 10 do last = last - 1 end
  if last == 0 then return nil, offset end
  data = data:sub(1, last)
  return data, offset + #data
end
local log = function(s) logs[#logs + 1] = s end
assert(load(INJECT_SRC, "@inject.lua"))()(CM, K, log)
assert(load(LINES_SRC, "@lines.lua"))()(CM, K, log)
-- the line as the engine holds it
local entity = ""
CM.lineKeyOf[108664] = "b:6"
function CM.lineKeyFor(lid) return lid == 108664 and "b:6" or nil end
function CM.lineIdFor(k) return k == "b:6" and 108664 or nil end
function CM.lineSnapshot(lid) return { name = "Line%201", color = "0.9,0.2,0.2", wait = 180, stops = entity, alts = "" } end
local P = {}
for sg, x in STATION_POS:gmatch("(%d+)=(%d+)") do P[tonumber(sg)] = tonumber(x) end
function CM.stationGroupPos(sg) if P[sg] then return P[sg], 0 end end
function CM.stationPosInGroup() return nil end
local H = {}
function H.poll() CM.pollInject() end
-- apply the oldest waiting update the way execLine records it: the list before, then after.
-- The engine's own confirmation (the updateLine callback) is H.confirm: it lags the apply.
function H.applyNext()
  local c = table.remove(CM.queue, 1)
  if not c then return nil end
  CM.lineHistNote(c.key, entity, "")
  CM.lineHistNote(c.key, c.stops or "", c.alts or "")
  entity = c.stops or ""
  now = now + 0.4
  return c.seq
end
function H.confirm() if CM.lineSentDone then CM.lineSentDone("b:6", entity) end end
function H.lastStops() local s = sched[#sched]; return s and s.stops end
function H.nsched() return #sched end
function H.entity() return entity end
function H.nbases() local h = CM.lineHist and CM.lineHist["b:6"]; return h and #h or 0 end
function H.baseFor(stops) local b = CM.lineBaseFor("b:6", stops, { stops = entity, alts = "" }); return b and b.stops end
function H.logs() return table.concat(logs, "\n") end
function H.holdResync(on) CM.resyncHold = on or nil end
function H.sentStops() local s = CM.lineSent and CM.lineSent["b:6"]; return s and s.stops end
function H.pendingStops() local p = CM.linePending("b:6"); return p and p.stops end
return H
''')


def main():
    d = tempfile.mkdtemp()
    path = os.path.join(d, "lockstep_inject_b.txt")
    open(path, "wb").close()
    H = runtime(path)

    def click(sgs):
        with open(path, "ab") as f:
            f.write(("ARMED 1\n" + click_line(sgs) + "\n").encode())
        H.poll()

    s158, s161, s164, s167 = (stop_str(x) for x in (107158, 107161, 107164, 107167))

    # 1. first station
    click([107158])
    check("click 1: one stop scheduled", H.lastStops() == s158, str(H.lastStops()))

    # 2. second station while click 1 still waits: the editor still shows the empty list
    click([107161])
    check("click 2 (click 1 waiting): both stops", H.lastStops() == f"{s158};{s161}", str(H.lastStops()))

    # click 1 applies before the next click is read
    H.applyNext()
    check("click 1 applied: the line holds stop 1", H.entity() == s158)

    # 3. third station, built by the editor from the EMPTY list it last saw
    click([107164])
    check("click 3 (built from the empty list): all three stops, stop 1 kept",
          H.lastStops() == f"{s158};{s161};{s164}", str(H.lastStops()) + "\n" + H.logs()[-400:])

    H.applyNext()   # click 2's update
    # 4. fourth station, built from the one-stop list
    click([107158, 107167])
    check("click 4 (built from the one-stop list): four stops",
          H.lastStops() == f"{s158};{s161};{s164};{s167}", str(H.lastStops()))

    # everything applies
    while H.applyNext():
        pass
    check("all applied: the line holds four stops", H.entity() == f"{s158};{s161};{s164};{s167}", H.entity())

    # 5. remove the stop just added, nothing waiting: a removal, not a no-op
    click([107158, 107161, 107164])
    check("remove the last stop: three stops scheduled", H.lastStops() == f"{s158};{s161};{s164}", str(H.lastStops()))

    # 6. A BURST OF 14 with the engine's confirmations lagging the whole way: the editor
    # still shows the one-stop list after click 1, every later click adds one station to
    # THAT list, and each applies before the next is read.
    print("== a burst of 14 clicks, nothing confirmed until the end")
    path = os.path.join(tempfile.mkdtemp(), "lockstep_inject_b.txt")
    open(path, "wb").close()
    H = runtime(path)

    def click2(sgs):
        with open(path, "ab") as f:
            f.write(("ARMED 1\n" + click_line(sgs) + "\n").encode())
        H.poll()

    sgs = sorted(POS)[:14]
    strs = [stop_str(x) for x in sgs]
    click2([sgs[0]])
    H.applyNext()
    burst_ok = True
    for k in range(1, 14):
        click2([sgs[0], sgs[k]])                       # built from the stale one-stop list
        want = ";".join(strs[:k + 1])
        if H.lastStops() != want:
            burst_ok = False
            check(f"click {k + 1} of the burst keeps every earlier stop ({k + 1} stops)", False,
                  f"got {H.lastStops().count(';') + 1} stop(s); bases kept: {H.nbases()}")
            break
        H.applyNext()
    check("every click of a 14-click burst merged against its true base", burst_ok)
    check("the line holds all 14 stops", H.entity() == ";".join(strs), f"{H.entity().count(';') + 1} stops")
    check("no base was evicted while the burst was in flight (28 lists kept)", H.nbases() >= 28, str(H.nbases()))
    # nothing queued, nothing confirmed yet: the lists stay
    H.baseFor(";".join(strs[:1] + strs[13:14]))
    check("still unconfirmed: the lists stay", H.nbases() >= 28, str(H.nbases()))
    # the engine confirms the last update: the line's edits have drained
    H.confirm()
    base = H.baseFor(";".join(strs[:13]))
    check("drained: a click one stop short of the entity bases on the entity", base == ";".join(strs), str(base))
    check("drained: only the last update's before/after lists remain", H.nbases() == 2, str(H.nbases()))

    # 7. A CLICK THE SCHEDULER DID NOT QUEUE (a resync hold): it must not be noted as "on
    # its way", or the next click merges onto a list the player never made and the
    # phantom pins every base of the line until the next send overwrites it.
    print("== a click under a resync hold: nothing queued, nothing noted")
    H.holdResync(True)
    n = H.nsched()
    click2([sgs[0]])                                    # would cut the line to one stop
    check("under a resync hold nothing is scheduled", H.nsched() == n, f"{H.nsched()} vs {n}")
    check("...and no list is noted as on its way", H.sentStops() is None and H.pendingStops() is None,
          f"sent={H.sentStops()} pending={H.pendingStops()}")
    check("...loudly", "b:6 was not queued (a resync hold, or no clock yet)" in H.logs())
    check("...and the line's bases are not pinned by it", H.nbases() == 2, str(H.nbases()))
    H.holdResync(False)
    click2(sgs[:13])                                    # remove the last stop, built from the entity
    check("the next click builds on the entity, not on the phantom list: 13 stops",
          H.lastStops() == ";".join(strs[:13]), f"{H.lastStops().count(';') + 1} stop(s)")

    # 8. A RE-SET OF THE STOP JUST ADDED while its add is still on its way (line 121756,
    # 2026-09-19). The editor keeps showing the list it built: [A1,B0] shipped, then the
    # editor re-sets B's platform to 1 -> [A1,B1]. Read against the entity's [A1] that was
    # "B1 added", and the merge put B1 beside the B0 still on its way: B twice.
    print("== a platform / wait-time re-set of a stop still on its way")

    def fresh():
        path = os.path.join(tempfile.mkdtemp(), "lockstep_inject_b.txt")
        open(path, "wb").close()
        H = runtime(path)

        def click3(stops):
            with open(path, "ab") as f:
                f.write(("ARMED 1\n" + click_line2(stops) + "\n").encode())
            H.poll()
        return H, click3

    A, B, C = 107158, 107161, 107164
    H, click3 = fresh()
    click3([(A, 1, 0)])
    H.applyNext(); H.confirm()
    click3([(A, 1, 0), (B, 0, 0)])                       # add B (platform 0), on its way
    click3([(A, 1, 0), (B, 1, 0)])                       # re-set B to platform 1, built from the shipped list
    check("platform re-set while the add waits: B once, on platform 1",
          H.lastStops() == f"{stop_str2(A, 1)};{stop_str2(B, 1)}", str(H.lastStops()))
    while H.applyNext():
        pass
    check("...the line holds A and B once each", H.entity() == f"{stop_str2(A, 1)};{stop_str2(B, 1)}", H.entity())

    H, click3 = fresh()
    click3([(A, 1, 0)])
    H.applyNext(); H.confirm()
    click3([(A, 1, 0), (B, 0, 0)])
    H.applyNext()                                        # applied, but the engine has not confirmed it yet
    click3([(A, 1, 0), (B, 1, 0)])
    check("platform re-set after the add applied (unconfirmed): B once",
          H.lastStops() == f"{stop_str2(A, 1)};{stop_str2(B, 1)}", str(H.lastStops()))

    H, click3 = fresh()
    click3([(A, 0, 0)])
    H.applyNext(); H.confirm()
    click3([(A, 0, 0), (B, 0, 0)])
    click3([(A, 0, 0), (B, 0, 30)])                      # minimum wait of the stop just added
    check("wait-time re-set while the add waits: B once, with the new wait",
          H.lastStops() == f"{stop_str2(A)};{stop_str2(B, 0, 30)}", str(H.lastStops()))

    # 9. removing a stop whose add is still on its way: a removal, not "nothing changed"
    # against the entity (which merged onto the waiting list and kept the stop)
    H, click3 = fresh()
    click3([(A, 0, 0)])
    H.applyNext(); H.confirm()
    click3([(A, 0, 0), (B, 0, 0)])
    click3([(A, 0, 0)])
    check("remove the stop still on its way: one stop", H.lastStops() == stop_str2(A), str(H.lastStops()))

    # 10. the capture's own sequence (a's line 121756): add, add-with-auto-flip (the
    # editor re-sets B's platform as it adds C: two changes in one click), re-set, re-set,
    # remove, remove, add, re-set, add -- every other click lands before the next is read;
    # never a duplicate stop
    print("== the line 121756 click sequence, every other click landing")
    H, click3 = fresh()
    seq = [[(A, 1, 0)], [(A, 1, 0), (B, 0, 0)], [(A, 1, 0), (B, 1, 0), (C, 1, 0)], [(A, 1, 0), (B, 0, 0), (C, 1, 0)],
           [(A, 1, 0), (B, 1, 0), (C, 1, 0)], [(A, 1, 0), (B, 1, 0)], [(A, 1, 0)], [(A, 1, 0), (B, 0, 0)],
           [(A, 1, 0), (B, 1, 0)], [(A, 1, 0), (B, 1, 0), (C, 1, 0)]]
    dup = None
    for k, stops in enumerate(seq):
        click3(stops)
        got = H.lastStops()
        want = ";".join(stop_str2(*x) for x in stops)
        if got != want:
            dup = f"click {k + 1}: shipped {got!r}, the editor's list was {want!r}"
            break
        if k % 2 == 1:
            H.applyNext()                               # every other click lands before the next is read
    check("the 121756 sequence ships every click as the editor built it", dup is None, dup or "")
    while H.applyNext():
        pass
    check("...and the line ends as the editor showed it", H.entity() == ";".join(stop_str2(*x) for x in seq[-1]), H.entity())

    print()
    if fails:
        print(f"{len(fails)} FAILED")
        sys.exit(1)
    print("all passed")


if __name__ == "__main__":
    main()
