"""Exercise real navigation.lua in separate GUI/engine states with shared files.

No game needed. Requires lupa.lua52. Tests deliberately use unrelated process
clocks, packet loss/reordering, interrupted files, multiple peers and UI callbacks.
"""
from pathlib import Path
from lupa.lua52 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
lua = LuaRuntime(unpack_returned_tuples=True)
lua.globals().SOURCE = (ROOT / 'mod/mp_lockstep_1/res/scripts/mp/navigation.lua').read_text(encoding='utf-8')
lua.globals().NET = (ROOT / 'mod/mp_lockstep_1/res/scripts/mp/net.lua').read_text(encoding='utf-8')
lua.execute(r'''
T, FILES, WIRE, STATES = 1000, {}, {}, {}
local function widget(text)
  return {text=text, items={}, addItem=function(s,v) s.items[#s.items+1]=v end,
    setLayout=function(s,v) s.layout=v end, onClick=function(s,v) s.click=v end,
    setEnabled=function(s,v) s.enabled=v end, setText=function(s,v) s.text=v end}
end
function state(o, gui)
  local s={o=o,gui=gui,pid=o=='a' and '11' or '22',cam={100,200,500,1,0.5},
    terrain={900,800,0},zones={},moves={},held=false,writes=0}
  s.K={BASE=o..'/', INSTANCE=o,PROCESS_ID=s.pid}
  s.CM={recoveryGuiHeld=function() return s.held end,detectInstance=function() end,
    cursorColor=function() return 1,0.2,0.4 end,
    broadcast=function(line) WIRE[#WIRE+1]=line end}
  local renderer={getTerrainPos=function() return s.terrain end,
    getCameraController=function() return {setCameraData=function(_,pos,d,a,p)
      s.moves[#s.moves+1]={pos[1],pos[2],d,a,p} end} end}
  local env=setmetatable({os={time=function() return math.floor(T) end,
    clock=function() return T+(o=='a' and 400 or 90) end},
    game={gui={getCamera=function() return s.cam end},interface={setZone=function(id,p) s.zones[id]=p end}},
    api={type={Vec2f={new=function(x,y) return {x,y} end}},gui={
      util={getGameUI=function() return {getMainRendererComponent=function() return renderer end} end},
      comp={Button={new=widget},TextView={new=widget},Component={new=widget}},layout={BoxLayout={new=widget}}}},
    io={open=function(path,mode)
      if mode=='rb' then
        local data=FILES[path]; if not data then return nil end
        return {read=function(_,n) return data:sub(1,n) end,close=function() return true end}
      end
      if s.failOpen then return nil end
      return {write=function(_,v)
        s.writes=s.writes+1
        if s.failWrite then FILES[path]=v:sub(1,8); return nil end
        FILES[path]=v; return true
      end,close=function() return not s.failClose end}
    end}}, {__index=_G})
  assert(load(SOURCE,'navigation','t',env))()(s.CM,s.K,function() end)
  STATES[#STATES+1]=s
  return s
end
function step(dt,drop)
  T=T+dt
  A.CM.navigationGuiTick(); B.CM.navigationGuiTick()
  AE.CM.navigationTick(); BE.CM.navigationTick()
  local packets=WIRE; WIRE={}
  for _,line in ipairs(packets) do
    if not drop then
      if line:find('o=a ',1,true) then BE.CM.navigationRecv(line) else AE.CM.navigationRecv(line) end
    end
  end
end
function run(seconds,drop)
  for _=1,math.ceil(seconds/0.11) do step(0.11,drop) end
end
A, AE, B, BE = state('a',true),state('a',false),state('b',true),state('b',false)
local box=widget(); B.CM.navigationPanel(box,{'a','b','c'})
local layout=box.items[1].layout
local goA=layout.items[3].layout.items[1]
local pingA=layout.items[3].layout.items[2]
local goC=layout.items[4].layout.items[1]
assert(not goA.enabled and not pingA.enabled)
run(1.5)
assert(goA.enabled and not goC.enabled and not pingA.enabled)
assert(#B.moves==0) -- presence never steals the camera
goA.click(); assert(#B.moves==1 and B.moves[1][1]==100 and B.moves[1][3]==500)

-- Mouse ping -> sender GUI -> engine -> dropped packet -> retry -> peer GUI.
FILES['a/tpf2mp_ping_key.txt']='11 12345\r\nend\r\n' -- native Windows text stream
run(0.7,true); run(1.5)
assert(B.zones.mpping_a and pingA.enabled)
assert(#B.moves==1)
local polygon=B.zones.mpping_a.polygon
assert(math.abs((polygon[1][1]+polygon[21][1])/2-900)<0.001)
B.cam={5,6,700,2,0.4}
pingA.click(); local jump=B.moves[2]
assert(jump[1]==900 and jump[2]==800 and jump[3]==700 and jump[4]==2)

-- A partial key file must not turn the same press into another ping.
FILES['a/tpf2mp_ping_key.txt']='11 12345\n'; run(0.3)
FILES['a/tpf2mp_ping_key.txt']='11 12345\nend\n'; run(0.3)
run(9)
assert(not B.zones.mpping_a and not pingA.enabled)
assert(not B.CM.navigationJump('a',true))

-- A second peer's ping is independent; duplicates and older sequence rejected.
local line='LSNAV o=c g=1000 s=1 c=1,2,600,1,0.5 p=4,30,40,2'
assert(BE.CM.navigationRecv(line)); assert(not BE.CM.navigationRecv(line))
assert(not BE.CM.navigationRecv(line:gsub('s=1','s=0')))
run(1)
assert(B.zones.mpping_c and goC.enabled)
local before=#B.moves; goC.click(); assert(B.moves[before+1][1]==1)

-- Strict input limits (no invalid data reaches the camera or zones).
for _,bad in ipairs({line..' junk',line:gsub('600','1e309'),line:gsub('600','0'),
  line:gsub('1,2,600','1,,2,600'),line:gsub('30,40,2','nan,40,2'),
  line:gsub('30,40,2','30,40,11'),line:gsub('o=c','o=toolong'),
  line:gsub('g=1000','g=99999999999999999999')}) do
  assert(not BE.CM.navigationDecode(bad),bad)
end

-- A pause in the simulation is not tied to the ping clock. No engine updates:
-- stale GUI snapshots must remove presence and markers and disable navigation.
T=T+12; B.CM.navigationGuiTick()
assert(not goA.enabled and not goC.enabled and not B.zones.mpping_c)
assert(not B.CM.navigationJump('c',false))

-- Old process keys and incomplete snapshots are not actions.
FILES['a/tpf2mp_ping_key.txt']='999 54321\nend\n'; run(1)
assert(not B.zones.mpping_a)
FILES['b/tpf2mp_nav_in_b.txt']='22 '..math.floor(T)..'\n10000 '..line
T=T+0.2; B.CM.navigationGuiTick(); assert(not B.zones.mpping_c)

-- Recovery disables sending and both kinds of camera jumps; consumes keys.
A.held=true; B.held=true
FILES['a/tpf2mp_ping_key.txt']='11 77777\nend\n'; run(1)
assert(not A.CM.navigationPing(true) and not B.CM.navigationJump('a',false))
assert(not B.zones.mpping_a)
A.held=false; B.held=false; run(1)
assert(not B.zones.mpping_a)

-- Failed outgoing write/close is retried; a fixed centre ping can be sent via UI.
A.failWrite=true; assert(A.CM.navigationPing(true)); run(0.8)
A.failWrite=false; A.failClose=true; run(0.8); A.failClose=false; run(1.5)
assert(B.zones.mpping_a)
pingA.click(); assert(B.moves[#B.moves][1]==100 and B.moves[#B.moves][2]==200)
FILES['b/tpf2mp_nav_in_b.txt']='partial'
T=T+0.2; B.CM.navigationGuiTick(); assert(B.zones.mpping_a)
T=T+4; B.CM.navigationGuiTick(); assert(not B.zones.mpping_a)

-- The real network dispatcher must route LSNAV outside the build-command queue.
local CNet, KNet = {ticks=1}, {EVENTS_FILE='events'}
assert(load(NET,'net'))()(CNet,KNet,function(err) error(err) end)
CNet.histPump=function() end
local routed
CNet.navigationRecv=function(value) routed=value end
CNet.readFrom=function() return line, #line end
CNet.pollEvents(); assert(routed==line)
CNet.resyncHold=true; routed=nil; CNet.pollEvents(); assert(routed==nil)

-- Wrapped camera angles and large-map zoom still publish a valid view.
A.cam={100,200,9000,-0.0000001,0.5}; run(1.5)
assert(B.CM.navigationJump('a',false)); assert(B.moves[#B.moves][3]==4000)

-- Existing key on GUI startup is only a baseline, never replayed.
local C=state('c',true)
FILES['c/tpf2mp_ping_key.txt']='22 99999\nend\n'
C.CM.navigationGuiTick()
assert(not C.zones.mpping_c)
print('navigation: multi-state transport, ping/jump UI, loss, expiry, malformed input, stale/partial files, recovery and retry PASS')
''')
