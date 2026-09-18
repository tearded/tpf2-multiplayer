-- Local confirmation sounds for cancelled UI commands replayed by the engine.
-- Cosmetic engine -> GUI state only; never send audio events to other peers.
return function(CM, K, log)
local names = { VBUY = "buyVehicle", VSELL = "sellVehicle", VLINE = "setLine",
                VDEPOT = "sendToDepot", VREPL = "replaceVehicle" }
local allowed = {}
for _, name in pairs(names) do allowed[name] = true end
-- An opaque local lifetime token, not simulation RNG or a network identity.
local epoch = tostring({}) .. ":" .. tostring(os.time())
local state = { epoch = epoch, seq = 0, events = {} }
local seen, order = {}, {}
local incoming, guiEpoch, guiSeq

function CM.actionSoundSuccess(c)
	local name = names[c.op]
	if not name or c.origin ~= K.INSTANCE or not K.STRICT_OPS[c.op] then return end
	local armed = tonumber(c.armed or (c.op == "VBUY" and 0 or 1))
	if armed ~= 1 then return end -- the original UI already handled it
	local key = tostring(c.op) .. ":" .. tostring(c.seq)
	if seen[key] then return end -- one sound for a batch sale / retried command
	seen[key] = true
	order[#order + 1] = key
	if #order > 128 then seen[table.remove(order, 1)] = nil end
	local events = {}
	for i = math.max(1, #state.events - 30), #state.events do events[#events + 1] = state.events[i] end
	events[#events + 1] = { seq = state.seq + 1, name = name }
	state = { epoch = epoch, seq = state.seq + 1, events = events }
end

function CM.actionSoundsSave() return state end
function CM.actionSoundsLoad(s)
	if type(s) ~= "table" or type(s.epoch) ~= "string" or type(s.seq) ~= "number"
			or type(s.events) ~= "table" then return end
	-- First sync / world reload only establishes a baseline. Saved sounds are
	-- never replayed; the fresh engine factory does not adopt saved audio state.
	if guiEpoch ~= s.epoch then guiEpoch, guiSeq = s.epoch, s.seq end
	incoming = s
end

function CM.actionSoundsGuiTick(muted)
	local s = incoming
	if not s then return end
	if muted then guiSeq = s.seq; return end
	if s.seq <= guiSeq then return end
	local ok, ui = pcall(function() return api.gui.util.getGameUI() end)
	if not ok or not ui then return end
	for _, e in ipairs(s.events) do
		if type(e.seq) == "number" and e.seq > guiSeq and e.seq <= s.seq and allowed[e.name] then
			-- Consume before calling: a failed audio device must not replay a
			-- confirmation every GUI frame or interfere with simulation commands.
			guiSeq = e.seq
			local played, err = pcall(function() ui:playSoundEffect(e.name) end)
			if not played then log("action sound unavailable: " .. tostring(err)) end
		end
	end
	guiSeq = s.seq
end
end
