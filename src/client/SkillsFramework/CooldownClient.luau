--!strict
-- CooldownClient: Mirrors server cooldown state via dispatcher-driven cooldown events.
-- Consumes events emitted by server CooldownService: cd_start, cd_adjust, cd_clear, cd_snapshot, cd_update.
-- Provides query helpers for UI.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Networking = require(ReplicatedStorage.Shared.Networking)
local TimeSync = require(script.Parent.Parent.Services.TimeSync)

-- Client-paced cooldowns: ignore server cooldown events for local UX gating.
local USE_SERVER_COOLDOWNS = false

local EVENT_NAME = "CooldownEvents"
local SNAPSHOT_REQUEST = "CooldownSnapshotRequest"
local COOLDOWN_CHANNEL_NAME = "Cooldown"
local dispatcher = Networking.client()
local dispatcherAny = dispatcher :: any
dispatcherAny:_ensureChannel(COOLDOWN_CHANNEL_NAME)

export type ChargeState = {
	current: number,
	max: number,
	rechargeEnd: number?,
	rechargeDuration: number,
}

export type CooldownRecord = {
	startAt: number,
	endAt: number,
	duration: number,
	charges: ChargeState?,
}

local cooldowns: { [string]: CooldownRecord } = {}
local localCooldowns: { [string]: CooldownRecord } = {}

local listeners: { (string, string?) -> () } = {} -- (eventType, key?)

local CooldownClient = {}

local function now(): number
	return os.clock()
end

local function toClientTime(value: number?): number?
	if typeof(value) ~= "number" then
		return nil
	end
	return TimeSync.toClientTime(value)
end

local function getRemainingFor(rec: CooldownRecord?): number
	if not rec then
		return 0
	end
	local rem = rec.endAt - now()
	if rem <= 0 then
		return 0
	end
	return rem
end

local function getBestRecord(key: string): CooldownRecord?
	local serverRec = cooldowns[key]
	local localRec = localCooldowns[key]
	local serverRem = getRemainingFor(serverRec)
	local localRem = getRemainingFor(localRec)
	if serverRem <= 0 and serverRec then
		cooldowns[key] = nil
		serverRec = nil
	end
	if localRem <= 0 and localRec then
		localCooldowns[key] = nil
		localRec = nil
	end
	if localRem > serverRem then
		return localRec
	end
	return serverRec or localRec
end

local function fire(eventType: string, key: string?)
	for _, cb in ipairs(listeners) do
		pcall(cb, eventType, key)
	end
end

function CooldownClient.onChanged(cb: (string, string?) -> ())
	table.insert(listeners, cb)
	return function()
		for i, f in ipairs(listeners) do
			if f == cb then
				table.remove(listeners, i)
				break
			end
		end
	end
end

function CooldownClient.get(key: string): CooldownRecord?
	return getBestRecord(key)
end

function CooldownClient.getRemaining(key: string): number
	local serverRec = cooldowns[key]
	local localRec = localCooldowns[key]
	local serverRem = getRemainingFor(serverRec)
	local localRem = getRemainingFor(localRec)
	if serverRem <= 0 and serverRec then
		cooldowns[key] = nil
		fire("clear", key)
	end
	if localRem <= 0 and localRec then
		localCooldowns[key] = nil
		fire("local_clear", key)
	end
	return math.max(serverRem, localRem)
end

function CooldownClient.getFraction(key: string): number
	local rec = getBestRecord(key)
	if not rec then
		return 0
	end
	if rec.duration <= 0 then return 1 end
	local elapsed = now() - rec.startAt
	return math.clamp(elapsed / rec.duration, 0, 1)
end

function CooldownClient.isOnCooldown(key: string): boolean
	return CooldownClient.getRemaining(key) > 0
end

function CooldownClient.iterate(): { { key: string, remaining: number, fraction: number } }
	local list: { { key: string, remaining: number, fraction: number } } = {}
	local seen: { [string]: boolean } = {}
	for key in pairs(cooldowns) do
		seen[key] = true
	end
	for key in pairs(localCooldowns) do
		seen[key] = true
	end
	for key in pairs(seen) do
		local rec = getBestRecord(key)
		if rec then
			local rem = rec.endAt - now()
			if rem > 0 then
				local frac = 0
				if rec.duration > 0 then
					frac = math.clamp((now() - rec.startAt) / rec.duration, 0, 1)
				else
					frac = 1
				end
				table.insert(list, { key = key, remaining = rem, fraction = frac })
			end
		end
	end
	return list
end

function CooldownClient.startLocal(key: string, duration: number)
	local d = math.max(0, duration)
	local s = now()
	localCooldowns[key] = {
		startAt = s,
		endAt = s + d,
		duration = d,
	}
	fire("local_start", key)
end

function CooldownClient.clearLocal(key: string)
	if localCooldowns[key] then
		localCooldowns[key] = nil
		fire("local_clear", key)
	end
end

function CooldownClient.requestSnapshot()
	task.spawn(function()
		local ok, resOrError = pcall(function()
			return dispatcherAny:request(SNAPSHOT_REQUEST, {}, {
				qos = "BACKGROUND",
			})
		end)
		if not ok then
			warn("CooldownClient: snapshot request failed", resOrError)
			return
		end
		local res = resOrError
		if typeof(res) == "table" and res.success == false then
			warn("CooldownClient: snapshot request rejected", res.error)
		end
	end)
end

-- New helpers for charges
function CooldownClient.getCharges(key: string): (number, number)
	local rec = cooldowns[key]
	if not rec or not rec.charges then
		return 0, 0
	end
	return rec.charges.current, rec.charges.max
end

function CooldownClient.getRechargeFraction(key: string): number
	local rec = cooldowns[key]
	if not rec or not rec.charges then return 0 end
	local ch = rec.charges
	if ch.current >= ch.max then return 1 end
	if not ch.rechargeEnd or ch.rechargeDuration <= 0 then return 0 end
	local remaining = ch.rechargeEnd - now()
	if remaining <= 0 then return 1 end
	local frac = 1 - (remaining / ch.rechargeDuration)
	return math.clamp(frac, 0, 1)
end

-- Event wiring (includes charges)
dispatcherAny:on(EVENT_NAME, function(payload)
	if not USE_SERVER_COOLDOWNS then
		return
	end
	local t = payload and payload.t
	if t == "cd_start" then
		local key = payload.key
		if key == "_GCD" then
			return
		end
		if key then
			local startAt = toClientTime(payload.startAt) or now()
			local endAt = toClientTime(payload.endAt) or startAt
			cooldowns[key] = {
				startAt = startAt,
				endAt = endAt,
				duration = payload.duration or (endAt - startAt),
				charges = payload.charges and {
					current = payload.charges.current or 0,
					max = payload.charges.max or 0,
					rechargeEnd = toClientTime(payload.charges.rechargeEnd),
					rechargeDuration = payload.charges.rechargeDuration or 0,
				} or nil,
			}
			fire("start", key)
		end
	elseif t == "cd_adjust" then
		local key = payload.key
		if key == "_GCD" then
			return
		end
		local rec = key and cooldowns[key]
		if rec then
			rec.startAt = toClientTime(payload.startAt) or rec.startAt
			rec.endAt = toClientTime(payload.endAt) or rec.endAt
			rec.duration = payload.duration or rec.duration
			if payload.charges then
				rec.charges = rec.charges or {
					current = 0, max = 0, rechargeEnd = nil, rechargeDuration = 0,
				}
				local ch = rec.charges :: ChargeState
				ch.current = payload.charges.current or ch.current
				ch.max = payload.charges.max or ch.max
				ch.rechargeEnd = toClientTime(payload.charges.rechargeEnd)
				ch.rechargeDuration = payload.charges.rechargeDuration or ch.rechargeDuration
			end
			fire("adjust", key)
		end
	elseif t == "cd_update" then
		local key = payload.key
		if key == "_GCD" then
			return
		end
		if key and cooldowns[key] then
			local rec = cooldowns[key]
			rec.charges = rec.charges or {
				current = 0, max = 0, rechargeEnd = nil, rechargeDuration = 0,
			}
			local chPayload = payload.charges
			if chPayload then
				local ch = rec.charges :: ChargeState
				ch.current = chPayload.current or ch.current
				ch.max = chPayload.max or ch.max
				ch.rechargeEnd = toClientTime(chPayload.rechargeEnd)
				ch.rechargeDuration = chPayload.rechargeDuration or ch.rechargeDuration
			end
			fire("update", key)
		end
	elseif t == "cd_clear" then
		local key = payload.key
		if key == "_GCD" then
			return
		end
		if key and cooldowns[key] then
			cooldowns[key] = nil
			fire("clear", key)
		end
	elseif t == "cd_snapshot" then
		local active = payload.active
		if type(active) == "table" then
			for k in pairs(cooldowns) do
				cooldowns[k] = nil
			end
			for k, v in pairs(active) do
				if k == "_GCD" then
					continue
				end
				local startAt = toClientTime(v.startAt) or now()
				local endAt = toClientTime(v.endAt) or startAt
				cooldowns[k] = {
					startAt = startAt,
					endAt = endAt,
					duration = v.duration or (endAt - startAt),
					charges = v.charges and {
						current = v.charges.current or 0,
						max = v.charges.max or 0,
						rechargeEnd = toClientTime(v.charges.rechargeEnd),
						rechargeDuration = v.charges.rechargeDuration or 0,
					} or nil,
				}
			end
			fire("snapshot", nil)
		end
	end
end)

return CooldownClient
