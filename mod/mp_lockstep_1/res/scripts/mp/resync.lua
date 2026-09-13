-- Guided recovery, ported from the archived fork's assisted resync.
-- No save/load or native world lock: the user saves the host and restarts ALL
-- games. A pause acknowledgement is not a drain acknowledgement or a SYNC.
return function(CM, K, log)
local NL = string.char(10)
local FRESH = 5
local guiBoot = os.time()
-- Per loaded Lua state; do not use random(), which belongs to the simulation.
CM.resyncToken = tostring(os.time()) .. tostring({}):gsub("[^%w]", "")

local function fresh(wall)
	local age = wall and os.time() - wall
	return age and age >= 0 and age <= FRESH
end

local function requestPath()
	return K.INSTANCE and K.BASE .. "resync_request_" .. K.INSTANCE .. ".txt"
end

local function snapshot()
	local complete = true
	for _, name in ipairs({ "lockstep_dash_" .. K.INSTANCE .. ".txt",
		"tpf2_capture_" .. K.INSTANCE .. ".txt", "tpf2_events_" .. K.INSTANCE .. ".txt",
		"lockstep_inject_" .. K.INSTANCE .. ".txt" }) do
		local ok = pcall(function()
			local src = assert(io.open(K.BASE .. name, "rb"))
			local size = src:seek("end")
			if not size or not src:seek("set", math.max(0, size - 262144)) then src:close(); error("seek failed") end
			local body = src:read(262144); src:close()
			if body == nil and size > 0 then error("read failed") end
			local dst = assert(io.open(K.BASE .. "resync_" .. CM.resyncToken .. "_" .. name, "wb"))
			local written = dst:write(body or ""); local closed = dst:close()
			assert(written and closed)
		end)
		if not ok then complete = false end
	end
	return complete and "OK" or "INCOMPLETE"
end

local function readRoster()
	-- Never lower the requirement on disconnect. Include joiners announced by
	-- the lobby even before their first heartbeat reaches this loaded world.
	CM.resyncExpected = math.max(CM.resyncExpected or 2, CM.rosterPlayers or 2)
	local f = io.open(K.BASE .. "tpf2_bridge_ctl.txt", "r")
	if f then
		local body = f:read(4096) or ""; f:close()
		CM.resyncExpected = math.max(CM.resyncExpected, tonumber(body:match("players=(%d+)")) or 2)
	end
end

function CM.beginResync()
	if CM.resyncHold or not K.INSTANCE then return end
	CM.resyncHold = true
	readRoster()
	CM.setSpeed(0, "guided resync")
	CM.resyncEvidence = snapshot()
	log("RESYNC: guided recovery hold; save the host under a new name and restart every game")
end

function CM.pollResyncRequest()
	if CM.resyncHold or not K.INSTANCE then return end
	local f = io.open(requestPath(), "r")
	if not f then return end
	local body = f:read(256) or ""; f:close()
	-- Require a complete write as well as the exact loaded-world token.
	if body == CM.resyncToken .. NL and CM.firstDesync then CM.beginResync() end
end

function CM.resyncReceive(line)
	local o, target, sender = line:match("^LSRESYNC o=([a-h]) target=(%w+) sender=(%w+)$")
	local pr = o and o ~= K.INSTANCE and CM.peers[o]
	if pr and target == CM.resyncToken and sender == pr.resyncToken and fresh(pr.resyncWall) then
		CM.beginResync()
	end
end

function CM.resyncHeartbeat(pr, line)
	pr.resyncToken = line:match(" r=(%w+)")
	pr.resyncHeld = line:match(" hold=(%d+)") == "1"
	pr.resyncWall = os.time()
end

function CM.resyncPump(now)
	if not CM.resyncHold then return false end
	if not CM.resyncRosterAt or os.time() ~= CM.resyncRosterAt then
		readRoster()
		CM.resyncRosterAt = os.time()
	end
	local speed
	pcall(function() speed = game.interface.getGameSpeed() end)
	if speed ~= 0 then CM.setSpeed(0, "resync hold") end
	if CM.ticks % K.HEARTBEAT_EVERY == 0 then
		CM.broadcast(string.format("LSTICK t=%d o=%s s=%d hi=%d r=%s hold=%d",
			math.floor(now), K.INSTANCE, CM.stepOf(now), CM.seqNo, CM.resyncToken, speed == 0 and 1 or 0))
		for o, pr in pairs(CM.peers) do
			if o ~= K.INSTANCE and pr.resyncToken and fresh(pr.resyncWall) then
				CM.broadcast("LSRESYNC o=" .. K.INSTANCE .. " target=" .. pr.resyncToken .. " sender=" .. CM.resyncToken)
			end
		end
	end
	local pending, count = {}, 0
	for o, pr in pairs(CM.peers) do
		if o ~= K.INSTANCE then
			count = count + 1
			if not pr.resyncToken or not pr.resyncHeld or not fresh(pr.resyncWall) then pending[#pending + 1] = o end
		end
	end
	table.sort(pending)
	local status = count < CM.resyncExpected - 1 and "WAITING FOR PEER"
		or (#pending > 0 and "WAITING: " .. table.concat(pending, ",") or "PEERS PAUSED")
	if speed ~= 0 then status = "WAITING FOR LOCAL PAUSE" end
	CM.dashVerdict = "RESYNC - " .. status
	-- Keep recovery visible in the existing dashboard and log tools, even though
	-- the normal capture/replay/pacing/update path is held. Never report SYNC here.
	local body = "boot=" .. tostring(CM.bootWall or 0) .. NL .. "wall=" .. os.time() .. NL
		.. "resynctoken=" .. CM.resyncToken .. NL .. "resync=1" .. NL
		.. "resyncstatus=" .. status .. NL .. "evidence=" .. CM.resyncEvidence .. NL
		.. "t=" .. math.floor(now) .. NL .. "desyncs=" .. (CM.desyncs or 0) .. NL
		.. "queued=" .. #(CM.queue or {}) .. NL .. "paused=" .. (speed == 0 and "yes" or "no") .. NL
		.. "speed=" .. tostring(speed or "?") .. NL .. "verdict=" .. CM.dashVerdict .. NL
	for _, prefix in ipairs({ "lockstep_dash_", "lockstep_status_" }) do
		local f = io.open(K.BASE .. prefix .. K.INSTANCE .. ".txt", "w")
		if f then f:write(body); f:close() end
	end
	return true
end

local function validDash(kv)
	return type(kv) == "table" and type(kv.resynctoken) == "string"
		and kv.resynctoken:match("^%w+$") and #kv.resynctoken <= 128
		and tonumber(kv.boot) and tonumber(kv.boot) >= guiBoot - 60 and fresh(tonumber(kv.wall))
end

local function instructions(kv)
	if kv.resync ~= "1" then
		return "Die Spielwelten stimmen nicht mehr ueberein.\n\n"
			.. "Resync vorbereiten fordert einen gemeinsamen Pausenstopp an.\n"
			.. "Danach speichert nur der Host; alle Spieler starten ihr Spiel neu.\n"
			.. "Der Host-Stand gilt. Nur beim Client vorhandene Aenderungen gehen verloren.\n\n"
			.. "Keine weiteren Bauaktionen ausfuehren."
	end
	return "RESYNC VORBEREITEN - " .. tostring(kv.resyncstatus or "Anfrage ausstehend") .. "\n\n"
		.. "Keine Bauaktionen ausfuehren; die Bauwerkzeuge sind nicht gesperrt.\n"
		.. "Warten, bis bei ALLEN Spielern PEERS PAUSED steht.\n\n"
		.. "1. Nur der Host: unter einem NEUEN Namen speichern.\n"
		.. "2. Alle Spiele regulaer beenden und neu starten.\n"
		.. "3. Neu verbinden. Host waehlt mit SAVE... genau diesen Stand.\n"
		.. "4. START GAME uebertraegt ihn. Den frisch uebertragenen Stand laden.\n"
		.. "5. Auf alle Spieler und einen frischen SYNC warten.\n\n"
		.. "Der Host-Stand gilt; reine Client-Aenderungen gehen verloren.\n"
		.. "Schliessen verbirgt nur dieses Fenster. Der Stopp bleibt bis zum Neustart.\n"
		.. "Lokale Diagnosekopien: " .. tostring(kv.evidence or "ausstehend")
end

function CM.resyncShow()
	local kv = CM.resyncGuiDash
	if not validDash(kv) or (kv.resync ~= "1" and (tonumber(kv.desyncs) or 0) < 1) then return end
	if CM.resyncWin then CM.resyncWin:setVisible(true, false); return end
	local box = api.gui.layout.BoxLayout.new("VERTICAL")
	CM.resyncText = api.gui.comp.TextView.new(instructions(kv))
	box:addItem(CM.resyncText)
	CM.resyncButton = api.gui.comp.Button.new(api.gui.comp.TextView.new("  Resync vorbereiten  "), true)
	CM.resyncButton:setEnabled(kv.resync ~= "1")
	CM.resyncButton:onClick(function()
		local current = CM.resyncGuiDash
		if not validDash(current) or current.resync == "1" or (tonumber(current.desyncs) or 0) < 1 then return end
		local path = requestPath()
		local f = path and io.open(path, "w")
		local written, closed
		if f then written = f:write(current.resynctoken .. NL); closed = f:close() end
		if not written or not closed then
			CM.resyncText:setText("Resync-Anfrage fehlgeschlagen. Erneut versuchen oder manuell pausieren.")
			return
		end
		CM.resyncRequested = current.resynctoken
		CM.resyncText:setText("Resync angefordert. Warte auf Bestaetigung; keine Bauaktionen ausfuehren.")
		CM.resyncButton:setEnabled(false)
	end)
	box:addItem(CM.resyncButton)
	local close = api.gui.comp.Button.new(api.gui.comp.TextView.new("  Schliessen  "), true)
	close:onClick(function() CM.resyncWin:setVisible(false, false) end)
	box:addItem(close)
	local body = api.gui.comp.Component.new("mpResync")
	body:setLayout(box)
	CM.resyncWin = api.gui.comp.Window.new("Gefuehrter Resync", body)
	CM.resyncWin:addHideOnCloseHandler()
	pcall(function() CM.resyncWin:setPosition(120, 220) end)
end

function CM.resyncGuiTick(kv)
	CM.resyncGuiDash = kv
	if not validDash(kv) then
		if CM.resyncWin then
			CM.resyncText:setText("Warte auf aktuellen Spielstatus. Keine Bauaktionen ausfuehren.")
			CM.resyncButton:setEnabled(false)
		end
		return
	end
	if CM.resyncGuiToken ~= kv.resynctoken then
		if CM.resyncWin then CM.resyncWin:setVisible(false, false) end
		CM.resyncWin, CM.resyncRequested, CM.resyncGuiSeen, CM.resyncGuiHeld = nil, nil, nil, nil
		CM.resyncGuiToken = kv.resynctoken
	end
	local held = kv.resync == "1"
	if held or (tonumber(kv.desyncs) or 0) > 0 then
		if not CM.resyncGuiSeen or (held and not CM.resyncGuiHeld) then
			CM.resyncShow()
			CM.resyncGuiSeen = true
		end
		CM.resyncGuiHeld = held
	end
	if CM.resyncWin then
		if held or CM.resyncRequested ~= kv.resynctoken then CM.resyncText:setText(instructions(kv)) end
		CM.resyncButton:setEnabled(not held and CM.resyncRequested ~= kv.resynctoken and (tonumber(kv.desyncs) or 0) > 0)
	end
end
end
