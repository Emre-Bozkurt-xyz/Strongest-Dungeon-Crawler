--!strict
-- CooldownService: Per-player skill & global cooldown tracking with mid-cooldown adjustment and future charge support.
-- Model A: Preserve original startAt; adjusting cooldown moves endAt and recomputes duration (duration = endAt - startAt).
-- Replication intentionally omitted here (handled alongside existing services locally) – add events separately when UI layer consumes.
-- Public API:
--   start(player, key, duration)
--   startGCD(player, duration?)
--   adjust(player, key, newRemaining?, deltaRemaining?, reason?)
--   isOnCooldown(player, key) -> (bool, remaining)
--   checkWithSource(player, key) -> (bool, source, remaining, total?)
--   getRemaining(player, key)
--   getGCDRemaining(player)
--   getAll(player) -> map key -> { startAt, endAt, duration, remaining }
--   forceClear(player, key, reason?) -> bool
--   (Charges scaffold) startWithCharges / consumeCharge (to be added later)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local okNet, NetRay = pcall(function()
	return require(ReplicatedStorage.Packages.NetRay)
end)
local net = okNet and NetRay or nil
local EVENT_NAME = "CooldownEvents"
local SNAPSHOT_REQUEST = "CooldownSnapshotRequest"
local eventHandle: any = nil
local snapshotRequestHandle: any = nil

local CooldownService = {}

-- Types
type CooldownEntry = {
	key: string,
	startAt: number,
	endAt: number,
	duration: number,
	charges: ({
		current: number,
		max: number,
		rechargeEnd: number?,
		rechargeDuration: number,
	})?,
}

local skillCD: { [Player]: { [string]: CooldownEntry } } = {}
local gcdData: { [Player]: { startAt: number, endAt: number, duration: number } } = {}
local DEFAULT_GCD = 1.0

-- Use os.clock() (monotonic) instead of tick() so that client (which also uses os.clock())
-- interprets endAt/startAt on the same time base. Mixing tick() (wall time / unix epoch)
-- with os.clock() (process uptime) produced gigantic remaining values client-side.
local function now(): number
	return os.clock()
end

local function ensure(player: Player)
	skillCD[player] = skillCD[player] or {}
	gcdData[player] = gcdData[player] or { startAt = 0, endAt = 0, duration = 0 }
end

-- Replication helpers (no-ops if NetRay missing)
local function emit(player: Player, payload: any)
	if eventHandle then
		-- NetRay server event API: eventHandle:FireClient(player, data)
		eventHandle:FireClient(player, payload)
	end
end

local function emitStart(player: Player, entry: CooldownEntry)
	emit(player, {
		t = "cd_start",
		key = entry.key,
		startAt = entry.startAt,
		endAt = entry.endAt,
		duration = entry.duration,
		charges = entry.charges and {
			current = entry.charges.current,
			max = entry.charges.max,
			rechargeEnd = entry.charges.rechargeEnd,
			rechargeDuration = entry.charges.rechargeDuration,
		} or nil,
	})
end

local function emitGCD(player: Player, g: { startAt: number, endAt: number, duration: number })
	emit(player, { t = "cd_start", key = "_GCD", startAt = g.startAt, endAt = g.endAt, duration = g.duration })
end

local function emitAdjust(player: Player, entry: CooldownEntry, reason: string?)
	emit(player, {
		t = "cd_adjust",
		key = entry.key,
		startAt = entry.startAt,
		endAt = entry.endAt,
		duration = entry.duration,
		reason = reason,
		charges = entry.charges and {
			current = entry.charges.current,
			max = entry.charges.max,
			rechargeEnd = entry.charges.rechargeEnd,
			rechargeDuration = entry.charges.rechargeDuration,
		} or nil,
	})
end

local function emitClear(player: Player, key: string, reason: string?)
	emit(player, { t = "cd_clear", key = key, reason = reason })
end

local function emitSnapshot(player: Player)
	local all = CooldownService.getAll(player)
	emit(player, { t = "cd_snapshot", active = all })
end

local function emitUpdateCharges(player: Player, entry: CooldownEntry, reason: string?)
	emit(player, {
		t = "cd_update",
		key = entry.key,
		charges = entry.charges and {
			current = entry.charges.current,
			max = entry.charges.max,
			rechargeEnd = entry.charges.rechargeEnd,
			rechargeDuration = entry.charges.rechargeDuration,
		},
		reason = reason,
	})
end

function CooldownService.start(player: Player, key: string, duration: number)
	ensure(player)
	local d = math.max(0, duration)
	local s = now()
	skillCD[player][key] = {
		key = key,
		startAt = s,
		endAt = s + d,
		duration = d,
	}
    local created: CooldownEntry = skillCD[player][key]
    emitStart(player, created)
end

function CooldownService.startGCD(player: Player, duration: number?)
	ensure(player)
	local d = math.max(0, duration or DEFAULT_GCD)
	local s = now()
	local g = gcdData[player]
	g.startAt = s
	g.endAt = s + d
	g.duration = d
    emitGCD(player, g)
end

local function remainingFor(entry: CooldownEntry, t: number): number
	return math.max(0, entry.endAt - t)
end

function CooldownService.getRemaining(player: Player, key: string): number
	ensure(player)
	local t = now()
	local e = skillCD[player][key]
	if not e then return 0 end
	local rem = remainingFor(e, t)
	if rem <= 0 then
		skillCD[player][key] = nil
		emitClear(player, key, "expire")
		return 0
	end
	return rem
end

function CooldownService.getGCDRemaining(player: Player): number
	ensure(player)
	local g = gcdData[player]
	local rem = math.max(0, g.endAt - now())
	if rem <= 0 then
		return 0
	end
	return rem
end

function CooldownService.isOnCooldown(player: Player, key: string): (boolean, number)
	ensure(player)
	local rem = CooldownService.getRemaining(player, key)
	if rem > 0 then
		return true, rem
	end
	local gcdRem = CooldownService.getGCDRemaining(player)
	if gcdRem > 0 then
		return true, gcdRem
	end
	return false, 0
end

function CooldownService.checkWithSource(player: Player, key: string): (boolean, string, number, number?)
	ensure(player)
	local t = now()
	local e = skillCD[player][key]
	if e then
		local rem = remainingFor(e, t)
		if rem > 0 then
			return true, "skill", rem, e.duration
		else
			skillCD[player][key] = nil
		end
	end
	local g = gcdData[player]
	if g and (g.endAt - t) > 0 then
		return true, "gcd", g.endAt - t, g.duration
	end
	return false, "none", 0, nil
end

function CooldownService.getAll(player: Player): { [string]: { startAt: number, endAt: number, duration: number, remaining: number } }
	ensure(player)
	local out: { [string]: { startAt: number, endAt: number, duration: number, remaining: number } } = {}
	local t = now()
	for key, e in pairs(skillCD[player]) do
		-- Process charge recharges lazily
		if e.charges then
			local changed = false
			while e.charges.rechargeEnd and e.charges.rechargeEnd <= t do
				e.charges.current += 1
				changed = true
				if e.charges.current < e.charges.max then
					e.charges.rechargeEnd = t + e.charges.rechargeDuration
				else
					e.charges.rechargeEnd = nil
					break
				end
			end
			if changed then
				emitUpdateCharges(player, e, "recharge")
			end
		end
		local rem = remainingFor(e, t)
		if rem > 0 then
			out[key] = { startAt = e.startAt, endAt = e.endAt, duration = e.duration, remaining = rem }
		else
			-- Only clear if main cooldown expired; keep charges structure if charges still present? If duration 0 treat as non-cooldown entry.
			if e.duration > 0 then
				-- main cooldown done
				skillCD[player][key] = nil
				emitClear(player, key, "expire")
			else
				-- if duration == 0 we rely solely on charges; keep entry
				out[key] = { startAt = e.startAt, endAt = e.endAt, duration = e.duration, remaining = 0 }
			end
		end
	end
	local g = gcdData[player]
	if g and (g.endAt - t) > 0 then
		out["_GCD"] = { startAt = g.startAt, endAt = g.endAt, duration = g.duration, remaining = g.endAt - t }
	end
	return out
end

function CooldownService.forceClear(player: Player, key: string, _reason: string?): boolean
	ensure(player)
	if skillCD[player][key] then
		local reason = _reason or "force"
		skillCD[player][key] = nil
		emitClear(player, key, reason)
		return true
	end
	return false
end

function CooldownService.adjust(player: Player, key: string, newRemaining: number?, deltaRemaining: number?, _reason: string?)
	ensure(player)
	local e = skillCD[player][key]
	if not e then return end -- ignore if not active
	local t = now()
	if newRemaining and deltaRemaining then
		error("CooldownService.adjust: supply only one of newRemaining or deltaRemaining")
	end
	if newRemaining then
		local nr = math.max(0, newRemaining)
		e.endAt = t + nr
		e.duration = e.endAt - e.startAt
	elseif deltaRemaining then
		e.endAt = e.endAt + deltaRemaining
		if e.endAt < t then
			-- immediate expiry
			skillCD[player][key] = nil
			emitClear(player, key, _reason or "adjust_expire")
			return
		end
		e.duration = e.endAt - e.startAt
	else
		return
	end
    emitAdjust(player, e, _reason)
end

-- Placeholder stubs for future charge system
function CooldownService.startWithCharges(player: Player, key: string, maxCharges: number, rechargeDuration: number, initialCharges: number?)
	ensure(player)
	if maxCharges < 1 then
		error("startWithCharges: maxCharges < 1")
	end
	local nowT = now()
	local init = initialCharges or maxCharges
	if init > maxCharges then
		init = maxCharges
	end
	local entry = skillCD[player][key]
	if not entry then
		local newEntry: CooldownEntry = {
			key = key,
			startAt = nowT,
			endAt = nowT, -- no active base cooldown yet
			duration = 0,
			charges = {
				current = init,
				max = maxCharges,
				rechargeEnd = (init < maxCharges) and (nowT + rechargeDuration) or nil,
				rechargeDuration = rechargeDuration,
			},
		}
		skillCD[player][key] = newEntry
		emitStart(player, newEntry)
		entry = newEntry
	else
		-- augment existing entry with charges (if needed)
		entry.charges = entry.charges or {
			current = init,
			max = maxCharges,
			rechargeEnd = (init < maxCharges) and (nowT + rechargeDuration) or nil,
			rechargeDuration = rechargeDuration,
		}
		emitAdjust(player, entry, "charges_init")
	end
end

function CooldownService.consumeCharge(player: Player, key: string, perUseCooldown: number?)
	ensure(player)
	local entry = skillCD[player][key]
	if not entry or not entry.charges then return false end
	if entry.charges.current <= 0 then return false end
	local t = now()
	entry.charges.current -= 1
	if entry.charges.current < entry.charges.max and not entry.charges.rechargeEnd then
		entry.charges.rechargeEnd = t + entry.charges.rechargeDuration
	end
	-- Per-use cooldown
	if perUseCooldown and perUseCooldown > 0 then
		entry.startAt = t
		entry.endAt = t + perUseCooldown
		entry.duration = perUseCooldown
		emitAdjust(player, entry, "consume_charge")
	else
		emitUpdateCharges(player, entry, "consume_charge")
	end
	return true
end

-- Batch retrieval helper (optional optimization for selective keys)
function CooldownService.getBatch(player: Player, keys: {string}): { [string]: { startAt: number, endAt: number, duration: number, remaining: number } }
	local result: { [string]: { startAt: number, endAt: number, duration: number, remaining: number } } = {}
	for _, key in ipairs(keys) do
		local all = CooldownService.getAll(player) -- simple approach; could optimize
		local rec = all[key]
		if rec then
			result[key] = rec
		end
	end
	return result
end

function CooldownService.getProgress(player: Player, key: string): (number, number)
	local e = skillCD[player] and skillCD[player][key]
	if not e then return 0, 0 end
	local t = now()
	local remaining = math.max(0, e.endAt - t)
	if e.duration <= 0 then
		return remaining, (remaining > 0 and 1 or 0)
	end
	local fraction = math.clamp((t - e.startAt) / e.duration, 0, 1)
	return remaining, fraction
end

local function cleanup(player: Player)
	skillCD[player] = nil
	gcdData[player] = nil
end

Players.PlayerRemoving:Connect(cleanup)

-- Lazy init of NetRay events to avoid race during module require ordering
if net and not eventHandle then
	eventHandle = net:RegisterEvent(EVENT_NAME)
	snapshotRequestHandle = net:RegisterRequestEvent(SNAPSHOT_REQUEST)
	if snapshotRequestHandle then
		snapshotRequestHandle:OnRequest(function(player)
			emitSnapshot(player)
			return true
		end)
	end
end

return CooldownService
