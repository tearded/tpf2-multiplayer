-- One-click recovery. The lobby owns the barrier and native save/load; this
-- module holds all Lua producers and fingerprints the freshly loaded world.
return function(CM, K, log)
local guiBoot = os.time()
CM.resyncToken = tostring(os.time()) .. tostring({}):gsub("[^%w]", "")
local function fresh(wall)
	local age = wall and os.time() - wall
	return age and age >= 0 and age <= 5
end
function CM.syncRead(name)
	local f = io.open(K.BASE .. name, "rb")
	if not f then return nil end
	local text = f:read(16384) or ""; f:close()
	if text:sub(-1) ~= "\n" then return nil end
	local kv = {}
	for key, value in text:gmatch("([%w_]+)=([^\r\n]*)[\r\n]") do kv[key] = value end
	return kv
end

function CM.syncRequest(kind)
	if not K.PROCESS_ID then pcall(CM.detectInstance) end
	local available = CM.syncRead("tpf2_sync_available.txt")
	if not available or available.protocol ~= "4" or available.pid ~= K.PROCESS_ID or not tonumber(available.wall)
		or math.abs(os.time()-tonumber(available.wall)) >= 5 then return false end
	CM.syncRequestNumber = (CM.syncRequestNumber or 0) + 1
	local f = io.open(K.BASE .. "tpf2_sync_request.txt", "wb")
	if not f then return false end
	local ok = f:write("pid=" .. available.pid .. "\ncmd=" .. kind .. "\nid=" ..
		CM.resyncToken .. tostring(CM.syncRequestNumber) .. "\n")
	local closed = f:close()
	return ok and closed
end

function CM.recoveryGuiHeld()
	if not K.PROCESS_ID then pcall(CM.detectInstance) end
	local state = CM.syncRead("tpf2_sync_lua.txt")
	if state and state.pid == K.PROCESS_ID and state.operation and state.epoch
		and #state.operation == 32 and not state.operation:find("[^0-9a-f]")
		and #state.epoch == 32 and not state.epoch:find("[^0-9a-f]")
		and tonumber(state.revision) and tonumber(state.revision) > (CM.recoveryGuiRevision or 0)
		and ({holding=true, waiting=true, saving=true, transferring=true, loading=true,
			checking=true, releasing=true, complete=true, error=true, aborted=true})[state.phase] then
		CM.recoveryGuiRevision = tonumber(state.revision)
		CM.recoveryGuiHold = state.phase ~= "complete"
	end
	return CM.recoveryGuiHold
end

function CM.autoSyncPump(now)
	local incoming = CM.syncRead("tpf2_sync_lua.txt")
	if incoming and incoming.pid == K.PROCESS_ID and incoming.operation and incoming.epoch
		and #incoming.operation == 32 and not incoming.operation:find("[^0-9a-f]")
		and #incoming.epoch == 32 and not incoming.epoch:find("[^0-9a-f]")
		and tonumber(incoming.revision) and tonumber(incoming.revision) >= 1
		and ({holding=true, waiting=true, saving=true, transferring=true, loading=true,
			checking=true, releasing=true, complete=true, error=true, aborted=true})[incoming.phase] then
		local old = CM.autoSync
		if (old or incoming.phase ~= "complete") and (not old or tonumber(incoming.revision) > tonumber(old.revision)) then
			CM.autoSync = incoming
			if not old or old.operation ~= incoming.operation then
				local speed; pcall(function() speed = game.interface.getGameSpeed() end)
				CM.autoResumeSpeed = speed or CM.baseSpeed or 0
				CM.setSpeed(0, "automatic world operation")
			end
			CM.autoFingerprint = nil
		end
	end
	local state = CM.autoSync
	if not state then return false end
	if state.phase == "complete" then
		if not CM.autoReleased or CM.autoReleased ~= state.epoch then
			local speed = tonumber(state.resume_speed)
			if speed ~= 0 and speed ~= 1 and speed ~= 2 and speed ~= 4 then return true end
			CM.autoReleased = state.epoch
			CM.recoveryReleasePacing(speed)
			CM.lgHolding, CM.resyncHold = false, false
			CM.baseSpeed = speed
			CM.setSpeed(speed, "all players verified the new world")
		end
		return false
	end
	-- Missing/partial control or an error NEVER releases an existing hold.
	CM.resyncHold = true
	local speed; pcall(function() speed = game.interface.getGameSpeed() end)
	if state.phase == "checking" and speed == 0 and not CM.autoFingerprint then
		local ok, hash, detail = pcall(CM.recoveryWorldHash, now)
		if ok and hash and detail and not detail:find("invalid", 1, true) then
			-- Deliberately bypass normal stamp deduplication and the running-only
			-- hash cadence: this is a fresh comparison of the paused loaded world.
			CM.autoFingerprint = hash .. ":" .. detail
		end
	end
	local f = io.open(K.BASE .. "tpf2_sync_lua_ack.txt", "wb")
	if f then
		f:write("pid=" .. tostring(K.PROCESS_ID) .. "\noperation=" .. state.operation ..
			"\nepoch=" .. state.epoch .. "\nrevision=" .. state.revision .. "\nphase=" .. state.phase ..
			"\nheld=1\npaused=" .. (speed == 0 and "1" or "0") ..
			"\nspeed=" .. tostring(CM.autoResumeSpeed or 0) ..
			"\nworld=" .. CM.resyncToken ..
			"\nfingerprint=" .. (CM.autoFingerprint or "") .. "\n")
		f:close()
	end
	if K.INSTANCE then
		local text = "boot=" .. tostring(CM.bootWall or 0) .. "\nwall=" .. os.time()
			.. "\nresynctoken=" .. CM.resyncToken .. "\nresync=1\nresyncstatus=" .. state.phase
			.. "\nverdict=RESYNC - " .. state.phase .. "\npaused=" .. (speed == 0 and "yes" or "no") .. "\n"
		for _, prefix in ipairs({"lockstep_dash_", "lockstep_status_"}) do
			local out = io.open(K.BASE .. prefix .. K.INSTANCE .. ".txt", "wb")
			if out then out:write(text); out:close() end
		end
	end
	return true
end

local function validDash(kv)
	return type(kv) == "table" and type(kv.resynctoken) == "string"
		and kv.resynctoken:match("^%w+$") and #kv.resynctoken <= 128
		and tonumber(kv.boot) and tonumber(kv.boot) >= guiBoot - 60 and fresh(tonumber(kv.wall))
end

local function instructions(kv)
	if kv.resync == "1" then
		return "Resync: " .. tostring(kv.resyncstatus or "Anfrage ausstehend")
			.. "\n\nSpeichern, Uebertragen, Neuladen und Pruefen laufen automatisch.\n"
			.. "Der Multiplayer-Status zeigt den Fortschritt und eventuelle Fehler."
	end
	return "Die Spielwelten stimmen nicht mehr ueberein.\n\n"
		.. "Neu synchronisieren haelt beide Spiele an, speichert den Host,\n"
		.. "uebertraegt den Stand und laedt ihn bei beiden Spielern neu.\n"
		.. "Nach erfolgreichem Abgleich geht es automatisch weiter.\n\n"
		.. "Der Host-Stand gilt; reine Client-Aenderungen gehen verloren."
end

function CM.resyncShow()
	local kv = CM.resyncGuiDash
	if not validDash(kv) or (kv.resync ~= "1" and (tonumber(kv.desyncs) or 0) < 1) then return end
	if CM.resyncWin then CM.resyncWin:setVisible(true, false); return end
	local box = api.gui.layout.BoxLayout.new("VERTICAL")
	CM.resyncText = api.gui.comp.TextView.new(instructions(kv))
	box:addItem(CM.resyncText)
	CM.resyncButton = api.gui.comp.Button.new(api.gui.comp.TextView.new("  Neu synchronisieren  "), true)
	CM.resyncButton:setEnabled(kv.resync ~= "1")
	CM.resyncButton:onClick(function()
		local current = CM.resyncGuiDash
		if not validDash(current) or current.resync == "1" or (tonumber(current.desyncs) or 0) < 1 then return end
		if not CM.syncRequest("sync_request") then
			CM.resyncText:setText("Automatischer Resync ist noch nicht verfuegbar. Beide Spieler muessen dieselbe Version in einer Host-Lobby verwenden.")
			return
		end
		CM.resyncRequested = current.resynctoken
		CM.resyncRequestedAt = os.time()
		CM.resyncText:setText("Resync angefordert. Warte auf Bestaetigung; keine Bauaktionen ausfuehren.")
		CM.resyncButton:setEnabled(false)
	end)
	box:addItem(CM.resyncButton)
	local close = api.gui.comp.Button.new(api.gui.comp.TextView.new("  Schliessen  "), true)
	close:onClick(function() CM.resyncWin:setVisible(false, false) end)
	box:addItem(close)
	local body = api.gui.comp.Component.new("mpResync")
	body:setLayout(box)
	CM.resyncWin = api.gui.comp.Window.new("Neu synchronisieren", body)
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
	if CM.resyncGuiHeld and not held and (tonumber(kv.desyncs) or 0) == 0 then
		if CM.resyncWin then CM.resyncWin:setVisible(false, false) end
		CM.resyncGuiSeen = nil
	end
	if not held and CM.resyncRequested and os.time() - (CM.resyncRequestedAt or 0) > 5 then
		CM.resyncRequested = nil
	end
	if held or (tonumber(kv.desyncs) or 0) > 0 then
		if not CM.resyncGuiSeen or (held and not CM.resyncGuiHeld) then
			CM.resyncShow()
			CM.resyncGuiSeen = true
		end
	end
	CM.resyncGuiHeld = held
	if CM.resyncWin then
		if held or CM.resyncRequested ~= kv.resynctoken then CM.resyncText:setText(instructions(kv)) end
		CM.resyncButton:setEnabled(not held and CM.resyncRequested ~= kv.resynctoken and (tonumber(kv.desyncs) or 0) > 0)
	end
end
end
