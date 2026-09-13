"""Guided recovery: production Lua 5.2, real files, simulated peers/engine/UI.

Does not claim a live game save/restart/transfer test. No native commands or
network access are used; every world-changing mock fails if reached in a hold.
"""
from pathlib import Path
from tempfile import TemporaryDirectory
import lupa.lua52 as lupa

ROOT = Path(__file__).resolve().parents[1]
MP = ROOT / 'mod/mp_lockstep_1/res/scripts/mp'
LOCKSTEP = (ROOT / 'mod/mp_lockstep_1/res/config/game_script/lockstep.lua').read_text(encoding='utf-8')
checks = 0


def check(label, condition):
    global checks
    assert condition, label
    checks += 1
    print('ok  ' + label)


def runtime(base, letter, diagnostics=True):
    base.mkdir(parents=True, exist_ok=True)
    if diagnostics:
        for name in (f'lockstep_dash_{letter}.txt', f'tpf2_capture_{letter}.txt',
                     f'tpf2_events_{letter}.txt', f'lockstep_inject_{letter}.txt'):
            (base / name).write_bytes(b'x' * 300000)
    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    lua.globals().base = base.as_posix() + '/'
    lua.globals().letter = letter
    lua.execute('''
        wall=10000; speed=2; pauseRequests=0; asynchronous=false
        os.time=function() return wall end
        os.clock=function() return wall end
        CM={peers={},ticks=2,seqNo=12,desyncs=1,bootWall=wall,queue={},firstDesync={t=4}}
        K={BASE=base,INSTANCE=letter,HEARTBEAT_EVERY=2,EVENTS_FILE=base..'events'}
        function CM.setSpeed(v)
            assert(v==0); pauseRequests=pauseRequests+1
            if not asynchronous then speed=v end
        end
        function CM.stepOf(v) return math.floor(v/0.2) end
        function CM.peerFor(o)
            CM.peers[o]=CM.peers[o] or {hashes={},details={}}
            return CM.peers[o]
        end
        function CM.gameTime() return 100 end
        function CM.detectInstance() return true end
        function forbidden() error('world/capture/pacing reached in hold') end
        CM.sampleSimRate=forbidden; CM.cmVehRecheck=forbidden
        CM.pollInject=forbidden; CM.histServe=forbidden; CM.onNack=forbidden
        game={interface={getGameSpeed=function() return speed end}}
        sent={}; function CM.broadcast(s) sent[#sent+1]=s end
        function CM.readFrom() local d=incoming; incoming=nil; return d,0 end
        log=function() end
    ''')
    for module in ('net.lua', 'resync.lua'):
        lua.execute((MP / module).read_text(encoding='utf-8'))(lua.globals().CM, lua.globals().K, lua.globals().log)
    # Export no test-only production hook: feed the real pollEvents reader.
    lua.execute('function receive(line) incoming=line.."\\n"; CM.pollEvents() end')
    return lua


def tick(lua):
    lua.execute('CM.ticks=CM.ticks+2; CM.resyncPump(100)')


def relay(sender, receiver):
    for line in list(sender.globals().sent.values()):
        receiver.globals().receive(line)
    sender.execute('sent={}')


def dash(base, letter='a'):
    return (base / f'lockstep_dash_{letter}.txt').read_text()


with TemporaryDirectory() as temporary:
    root = Path(temporary)
    a, b = runtime(root / 'a', 'a'), runtime(root / 'b', 'b')
    at, bt = a.globals().CM.resyncToken, b.globals().CM.resyncToken
    a.globals().receive(f'LSTICK t=100 o=b s=500 hi=12 r={bt}')
    b.globals().receive(f'LSTICK t=100 o=a s=500 hi=12 r={at}')
    request = root / 'a/resync_request_a.txt'
    for text in ('stale-world\n', at, at + '\njunk'):
        request.write_text(text)
        a.execute('CM.pollResyncRequest()')
        check('reject stale or incomplete request: ' + repr(text[:20]), not a.globals().CM.resyncHold)
    request.write_text(at + '\n')
    a.execute('CM.firstDesync=nil; CM.pollResyncRequest()')
    check('local request needs a detected desync', not a.globals().CM.resyncHold)
    a.execute('CM.firstDesync={t=4}; CM.pollResyncRequest()')
    tick(a)
    check('request pauses local game', a.globals().speed == 0 and a.globals().CM.resyncHold)
    check('peer has not acknowledged yet', 'WAITING: b' in dash(root / 'a'))
    snapshots = list((root / 'a').glob('resync_*_*.txt'))
    snapshots = [p for p in snapshots if not p.name.startswith('resync_request_')]
    check('four bounded diagnostic tails', len(snapshots) == 4 and all(p.read_bytes() == b'x' * 262144 for p in snapshots))
    for packet in (f'LSRESYNC o=a target=stale sender={at}',
                   f'LSRESYNC o=c target={bt} sender=unknown',
                   f'LSRESYNC o=a target={bt} sender=wrong',
                   f'LSRESYNC o=a target={bt} sender={at} trailing'):
        b.globals().receive(packet)
        check('reject invalid remote request', not b.globals().CM.resyncHold)
    b.execute('wall=10006')
    b.globals().receive(f'LSRESYNC o=a target={bt} sender={at}')
    check('reject request from stale peer', not b.globals().CM.resyncHold)
    b.execute('wall=10000; CM.firstDesync=nil; CM.desyncs=0')
    a.execute('sent={}')  # first request lost
    tick(a)
    relay(a, b)
    check('repeated request reaches a peer without local desync', b.globals().CM.resyncHold and b.globals().speed == 0)
    tick(b)
    relay(b, a)
    tick(a)
    check('fresh pause acknowledgements reach ready status', 'PEERS PAUSED' in dash(root / 'a'))
    check('status file agrees with dashboard', (root / 'a/lockstep_status_a.txt').read_text() == dash(root / 'a'))
    a.execute('CM.resyncExpected=3')
    tick(a)
    check('missing third player blocks ready', 'WAITING FOR PEER' in dash(root / 'a'))
    a.execute('CM.resyncExpected=2; speed=4; asynchronous=true')
    tick(a)
    check('pause must be observed, not merely requested', 'WAITING FOR LOCAL PAUSE' in dash(root / 'a'))
    a.execute('asynchronous=false')
    tick(a)
    check('play attempt is paused again', a.globals().speed == 0)
    a.execute('wall=10006')
    tick(a)
    check('old acknowledgement expires', 'WAITING: b' in dash(root / 'a'))
    a.execute('wall=10000')
    a.globals().receive('LSTICK t=100 o=b s=500 hi=12 hold=1')
    tick(a)
    check('old build without recovery token cannot acknowledge', 'WAITING: b' in dash(root / 'a'))
    a.execute('wall=9999')
    tick(a)
    check('future acknowledgement cannot satisfy freshness', 'WAITING: b' in dash(root / 'a'))
    # A full inbound batch uses the real parser. No command scheduling, NACK
    # response, catch-up history or speed control is permitted during recovery.
    a.execute('CM.histPump=forbidden; CM.queue={}; CM.effSpeed=0')
    for packet in ('LSCMD op=ROAD at=100 origin=b seq=99', 'LSEFF v=4',
                   'LSNEED t=90 o=b', 'LSNACK o=a seq=3'):
        a.globals().receive(packet)
    a.execute('CM.scheduleLocal("ROAD", {}); assert(#CM.queue==0 and CM.seqNo==12 and CM.effSpeed==0)')
    check('command producers and inbound replay are held', True)
    prefix = LOCKSTEP.split('\t\tupdate = function()', 1)[1].split('\t\t\tpcall(CM.sampleSimRate)', 1)[0]
    a.execute('CM.cmVehPending=true; function updateProbe()' + prefix + '\nforbidden() end; updateProbe()')
    check('production update exits before deferred repair/capture/pacing', True)
    a.execute('wall=50000; CM.beginResync()')
    tick(a)
    check('no timeout releases hold or replaces evidence', a.globals().CM.resyncHold and all(p.read_bytes() == b'x' * 262144 for p in snapshots))
    fresh = runtime(root / 'a', 'a', diagnostics=False)
    fresh.execute('CM.pollResyncRequest()')
    check('fresh world rejects old local request', not fresh.globals().CM.resyncHold)
    missing = runtime(root / 'missing', 'c', diagnostics=False)
    missing.execute('CM.beginResync()')
    check('missing diagnostics do not abandon the pause', missing.globals().CM.resyncEvidence == 'INCOMPLETE' and missing.globals().speed == 0)
    roster = runtime(root / 'roster', 'a')
    (root / 'roster/tpf2_bridge_ctl.txt').write_text('players=4\n')
    roster.execute('CM.beginResync()')
    check('lobby roster sets required player count', roster.globals().CM.resyncExpected == 4)
    (root / 'roster/tpf2_bridge_ctl.txt').write_text('players=5\n')
    tick(roster)
    check('new roster member blocks completion before its first heartbeat', roster.globals().CM.resyncExpected == 5)
    (root / 'roster/tpf2_bridge_ctl.txt').write_text('players=2\n')
    roster.execute('wall=10001')
    tick(roster)
    check('disconnect cannot lower the recovery requirement', roster.globals().CM.resyncExpected == 5)
    # GUI widgets are simulated; callbacks and file requests are production Lua.
    ui = runtime(root / 'ui', 'b')
    ui.execute('''
        windows={}
        local function widget(text)
            return {text=text,visible=true,enabled=true,
                setText=function(self,t) self.text=t end,
                setEnabled=function(self,v) self.enabled=v end,
                setVisible=function(self,v) self.visible=v end,
                addHideOnCloseHandler=function(self) self.close=function() self.visible=false end end,
                onClick=function(self,f) self.click=f end,
                addItem=function() end, setLayout=function() end,
                setPosition=function() end}
        end
        api={gui={comp={TextView={new=widget},Button={new=widget},Component={new=widget},
            Window={new=function(t) local w=widget(t); windows[#windows+1]=w; return w end}},
            layout={BoxLayout={new=widget}}}}
        kv={boot='10000',wall='10000',resynctoken='world1',desyncs='1'}
        CM.resyncGuiTick(kv)
    ''')
    check('desync opens recovery independently of log reporting', len(ui.globals().windows) == 1)
    ui.execute('CM.resyncWin:setVisible(false,false); CM.resyncGuiTick(kv)')
    check('dismissed warning stays dismissed', not ui.globals().CM.resyncWin.visible)
    ui.execute('CM.resyncShow()')
    check('dashboard can reopen recovery', ui.globals().CM.resyncWin.visible)
    ui.execute('CM.resyncWin.close(); CM.resyncShow()')
    check('title-bar close hides a reusable window', len(ui.globals().windows) == 1 and ui.globals().CM.resyncWin.visible)
    # Turn the request path into a directory for a genuine open failure.
    ui_request = root / 'ui/resync_request_b.txt'
    ui_request.mkdir()
    ui.execute('CM.resyncButton.click()')
    check('write error keeps retry available', ui.globals().CM.resyncButton.enabled and 'fehlgeschlagen' in ui.globals().CM.resyncText.text)
    ui_request.rmdir()
    ui.execute('CM.resyncButton.click()')
    check('GUI writes complete token to this instance', ui_request.read_text() == 'world1\n')
    check('request waits for simulation confirmation', not ui.globals().CM.resyncButton.enabled and 'Bestaetigung' in ui.globals().CM.resyncText.text)
    ui.execute('CM.resyncGuiTick(kv)')
    check('pending request is not displayed as paused', 'Bestaetigung' in ui.globals().CM.resyncText.text)
    ui.execute("CM.resyncWin:setVisible(false,false); kv.resync='1'; kv.resyncstatus='WAITING: a'; kv.evidence='INCOMPLETE'; CM.resyncGuiTick(kv)")
    check('accepted recovery reopens with live status', ui.globals().CM.resyncWin.visible and 'WAITING: a' in ui.globals().CM.resyncText.text)
    ui.execute("kv.resyncstatus='PEERS PAUSED'; CM.resyncGuiTick(kv)")
    check('ready instructions still require host save and restart', 'NEUEN Namen' in ui.globals().CM.resyncText.text and 'PEERS PAUSED' in ui.globals().CM.resyncText.text)
    ui.execute('CM.resyncWin:setVisible(false,false); CM.resyncGuiTick(kv)')
    check('hiding active recovery does not reopen every tick', not ui.globals().CM.resyncWin.visible)
    ui.execute('wall=10010; CM.resyncGuiTick(kv)')
    check('stale dashboard cannot display ready', 'aktuellen Spielstatus' in ui.globals().CM.resyncText.text and not ui.globals().CM.resyncButton.enabled)
    ui.execute("wall=10000; kv={boot='10000',wall='10000',resynctoken='world2',desyncs='0'}; CM.resyncGuiTick(kv)")
    check('new healthy world clears previous recovery UI', ui.globals().CM.resyncWin is None)
    ui.execute("kv.resync='1'; kv.resyncstatus='PEERS PAUSED'; CM.resyncGuiTick(kv)")
    check('remote recovery opens without local desync', ui.globals().CM.resyncWin.visible and not ui.globals().CM.resyncButton.enabled)
    ui.execute((MP / 'stats.lua').read_text(encoding='utf-8'))(ui.globals().CM, ui.globals().K, ui.globals().log)
    check('stats prioritise recovery even without a local desync or peer columns', 'Guided resync: PEERS PAUSED' in ui.eval('CM.statusWords(kv,0)'))

print(f'PASS: {checks} guided resync checks (simulated engine/UI)')
