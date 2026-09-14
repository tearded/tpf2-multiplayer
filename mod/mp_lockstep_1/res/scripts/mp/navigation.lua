-- Cosmetic map navigation: camera presence and persistent, voluntary map pings.
-- GUI <-> engine uses bounded complete snapshots, just like cursors. No commands,
-- entity IDs, world writes or saved state. Remote packets never move the camera.
return function(CM, K, log)
local boot = os.time()
local generation = boot
local peers, drawn, buttons = {}, {}, {}
local lastGui, lastEngine, seq = -1, -1, 0
local lastPoll = -1
local keySeen, keyReady, mine, lastPing = nil, false, nil, -10
local latest = {}
local notice

local function number(s)
	local n = tonumber(s)
	if n and n == n and math.abs(n) <= 1000000 then return n end
end

local function camera(s)
	if type(s) ~= "string" or s:find(",,", 1, true) or s:sub(1,1) == "," or s:sub(-1) == "," then return nil end
	local a = {}
	for v in (s or ""):gmatch("[^,]+") do
		local n = number(v)
		if not n then return nil end
		a[#a+1] = n
	end
	if #a ~= 5 or a[3] < 1 or a[3] > 4000 or a[4] < 0 or a[4] > 2*math.pi or a[5] < 0 or a[5] > 1 then return nil end
	return a
end

function CM.navigationDecode(line)
	if type(line) ~= "string" or #line > 512 then return nil end
	local o, g, s, c, id, x, y, age = line:match("^LSNAV o=([a-z]+) g=(%d+) s=(%d+) c=([^ ]+) p=(%d+),([^,]+),([^,]+),([^, ]+)$")
	if not o or #o > 2 or #g > 12 or #s > 14 or #id > 14 then return nil end
	c, x, y, age = camera(c), number(x), number(y), number(age)
	if not c or not x or not y or not age or age < 0 or age > 10 then return nil end
	return {o=o, g=tonumber(g), s=tonumber(s), c=c, id=tonumber(id), x=x, y=y, age=age}
end

local function read(name)
	if not K.BASE then return nil end
	local f = io.open(K.BASE .. name, "rb")
	if not f then return nil end
	local s = f:read(16385); f:close()
	if not s or #s > 16384 or s:sub(-5) ~= "\nend\n" then return nil end
	return s:sub(1, -6)
end

local function write(name, s)
	local f = io.open(K.BASE .. name, "wb")
	if not f then return false end
	local ok = f:write(s .. "\nend\n")
	local closed = f:close()
	return ok and closed
end

local function file(incoming)
	return "tpf2mp_nav_" .. (incoming and "in_" or "out_") .. K.INSTANCE .. ".txt"
end

local function snapshot(name)
	local raw = read(name)
	if not raw then return nil end
	local pid, wall, body = raw:match("^(%d+) (%d+)\n(.*)$")
	wall = tonumber(wall)
	if pid ~= tostring(K.PROCESS_ID) or not wall or wall < boot or os.time()-wall < 0 or os.time()-wall > 3 then return nil end
	return body, wall
end

function CM.navigationRecv(line)
	local p = CM.navigationDecode(line)
	if not p or p.o == K.INSTANCE then return false end
	local prev = peers[p.o]
	if prev and (p.g < prev.g or (p.g == prev.g and p.s <= prev.s)) then return false end
	if not prev then
		local count = 0
		for _ in pairs(peers) do count = count + 1 end
		if count >= 16 then return false end
	end
	p.at = os.time()
	p.untilAt = p.at + 10 - p.age
	-- A heartbeat/retry must never restart a marker's ten-second life.
	if prev and p.g == prev.g and p.id == prev.id then p.untilAt = math.min(p.untilAt, prev.untilAt) end
	p.line = line
	peers[p.o] = p
	return true
end

function CM.navigationTick()
	if not K.INSTANCE or not K.PROCESS_ID then return end
	local clk, now = os.clock(), os.time()
	if clk-lastEngine < 0.2 then return end
	lastEngine = clk
	local body = snapshot(file(false))
	local p = body and CM.navigationDecode(body)
	if p and p.o == K.INSTANCE and (not CM.navigationSent or body ~= CM.navigationSent) then
		CM.broadcast(body)
		CM.navigationSent = body
	end
	local rows = {tostring(K.PROCESS_ID) .. " " .. now}
	for o, peer in pairs(peers) do
		if now-peer.at <= 3 then
			rows[#rows+1] = string.format("%.3f %s", peer.untilAt, peer.line)
		elseif now-peer.at > 30 then peers[o] = nil end
	end
	write(file(true), table.concat(rows, "\n"))
end

local function currentCamera()
	local c = game.gui.getCamera()
	local angle = math.floor((c[4] % (2*math.pi))*100000)/100000
	return camera(string.format("%.2f,%.2f,%.2f,%.5f,%.5f", c[1], c[2], math.max(1,math.min(4000,c[3])), angle, c[5]))
end

local function message(s)
	CM.navigationMessage = s
	if notice then notice:setText(s) end
end

function CM.navigationPing(center)
	if CM.recoveryGuiHeld() or not K.INSTANCE or not K.PROCESS_ID then return false end
	local clk = os.clock()
	if clk-lastPing < 1 then return false end
	local ok, pos = pcall(function()
		if center then return currentCamera() end
		return api.gui.util.getGameUI():getMainRendererComponent():getTerrainPos()
	end)
	local x, y
	if ok and pos then pcall(function() x, y = number(pos[1] or pos.x), number(pos[2] or pos.y) end) end
	if not x or not y then message("Move the mouse onto the map to ping."); return false end
	lastPing = clk
	mine = {id=math.max(1, math.floor(clk*1000)), x=x, y=y, at=clk, untilAt=os.time()+10, o=K.INSTANCE}
	lastGui = -1
	message("Here! Ping sent (10 seconds).")
	return true
end

function CM.navigationJump(o, ping)
	if CM.recoveryGuiHeld() then return false end
	local p = latest[o]
	if not p or os.time()-p.at > 3 or (ping and (p.id == 0 or os.time() >= p.untilAt)) then return false end
	local ok, err = pcall(function()
		local c = ping and currentCamera() or p.c
		if not c then error("camera unavailable") end
		local x, y = ping and p.x or c[1], ping and p.y or c[2]
		-- The documented GUI controller accepts map coordinates, never entity IDs.
		local renderer = api.gui.util.getGameUI():getMainRendererComponent()
		renderer:getCameraController():setCameraData(api.type.Vec2f.new(x, y), c[3], c[4], c[5])
	end)
	if not ok then log("navigation camera: " .. tostring(err)); message("Could not move the camera.") end
	return ok
end

local function draw(p, now, c)
	if p.id == 0 or now >= p.untilAt then return end
	local radius = math.max(3, math.min(250, (c and c[3] or 500)*0.025))
	local poly = {}
	for i=1,40 do
		local angle = (i-1)*2*math.pi/40
		poly[i] = {p.x+radius*math.cos(angle), p.y+radius*math.sin(angle)}
	end
	local r, g, b = CM.cursorColor(p.o)
	game.interface.setZone("mpping_" .. p.o, {polygon=poly, draw=true, drawColor={r,g,b,1}})
	drawn[p.o] = true
end

function CM.navigationGuiTick()
	if not K.INSTANCE or not K.PROCESS_ID then pcall(CM.detectInstance) end
	if not K.INSTANCE or not K.PROCESS_ID then return end
	local clk, now = os.clock(), os.time()
	if clk-lastPoll < 0.1 then return end
	lastPoll = clk
	local request = read("tpf2mp_ping_key.txt")
	local pid = request and request:match("^(%d+) %d+$")
	local held = CM.recoveryGuiHeld()
	if keyReady and request and request ~= keySeen and pid == tostring(K.PROCESS_ID) and not held then
		CM.navigationPing(false)
	end
	if request then keySeen = request end
	keyReady = true
	if held then mine, latest = nil, {} end
	local ok, c = pcall(currentCamera)
	if not ok then c = nil end
	if not held and c and (clk-lastGui >= 0.5 or lastGui < 0) then
		seq = math.max(seq+1, math.floor(clk*1000))
		local p = mine and clk-mine.at < 10 and mine or nil
		local line = string.format("LSNAV o=%s g=%d s=%d c=%.2f,%.2f,%.2f,%.5f,%.5f p=%d,%.2f,%.2f,%.3f",
			K.INSTANCE, generation, seq, c[1],c[2],c[3],c[4],c[5], p and p.id or 0,p and p.x or 0,p and p.y or 0,p and clk-p.at or 10)
		if write(file(false), tostring(K.PROCESS_ID) .. " " .. now .. "\n" .. line) then lastGui = clk end
	end
	local body, wall
	if not held then body, wall = snapshot(file(true)) end
	if body then
		latest = {}
		for line in body:gmatch("[^\n]+") do
			local untilAt, wire = line:match("^([%d%.]+) (LSNAV .+)$")
			local p = wire and CM.navigationDecode(wire)
			if p and tonumber(untilAt) then
				p.untilAt, p.at = tonumber(untilAt), wall
				latest[p.o] = p
			end
		end
	end
	-- An interrupted file is not a withdrawal. Keep the last complete snapshot
	-- only until its original timestamp expires, never refresh it on a failed read.
	for o, p in pairs(latest) do if now-p.at > 3 then latest[o] = nil end end
	local wanted, active = {}, {}
	for o, p in pairs(latest) do
		if p.id > 0 and now < p.untilAt then wanted[o] = p; active[#active+1] = string.upper(o) end
	end
	if mine and now < mine.untilAt then wanted[K.INSTANCE] = mine end
	for o in pairs(drawn) do
		if not wanted[o] then game.interface.setZone("mpping_" .. o, nil); drawn[o] = nil end
	end
	for _, p in pairs(wanted) do draw(p, now, c) end
	table.sort(active)
	if #active > 0 then message("Here! " .. table.concat(active, ", ") .. " marked a spot.")
	elseif CM.navigationHadPing then message("Ping expired. Ctrl+Shift+P: ping under mouse.") end
	CM.navigationHadPing = #active > 0 or mine and now < mine.untilAt
	for o, row in pairs(buttons) do
		row.camera:setEnabled(not held and latest[o] ~= nil)
		row.ping:setEnabled(not held and wanted[o] ~= nil)
	end
end

function CM.navigationPanel(box, present)
	buttons = {}
	local layout = api.gui.layout.BoxLayout.new("VERTICAL")
	local function button(label, fn)
		local b = api.gui.comp.Button.new(api.gui.comp.TextView.new(label), true)
		b:onClick(fn)
		return b
	end
	notice = api.gui.comp.TextView.new(CM.navigationMessage or "Ctrl+Shift+P: ping under mouse (10s)")
	layout:addItem(notice)
	layout:addItem(button("  Here! Ping view centre  ", function() CM.navigationPing(true) end))
	for _, o in ipairs(present) do
		if o ~= K.INSTANCE then
			local origin = o
			local row = api.gui.layout.BoxLayout.new("HORIZONTAL")
			local cam = button("  Go to " .. string.upper(origin) .. "  ", function() CM.navigationJump(origin, false) end)
			local ping = button("  Go to ping " .. string.upper(origin) .. "  ", function() CM.navigationJump(origin, true) end)
			cam:setEnabled(false); ping:setEnabled(false)
			row:addItem(cam); row:addItem(ping)
			local comp = api.gui.comp.Component.new("mpNav_" .. origin); comp:setLayout(row); layout:addItem(comp)
			buttons[origin] = {camera=cam, ping=ping}
		end
	end
	local comp = api.gui.comp.Component.new("mpNavigation"); comp:setLayout(layout); box:addItem(comp)
end
end
