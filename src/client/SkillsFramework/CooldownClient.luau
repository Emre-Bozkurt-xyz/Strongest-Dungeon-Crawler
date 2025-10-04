--!strict
-- CooldownClient: Mirrors server cooldown state via NetRay replication events.
-- Consumes events emitted by server CooldownService: cd_start, cd_adjust, cd_clear, cd_snapshot, cd_update.
-- Provides query helpers for UI.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local okNet, NetRay = pcall(function()
	return require(ReplicatedStorage.Packages.NetRay)
end)

if not okNet then
	warn("CooldownClient: NetRay not available; client cooldowns disabled")
end

local EVENT_NAME = "CooldownEvents"
local SNAPSHOT_REQUEST = "CooldownSnapshotRequest"

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

local listeners: { (string, string?) -> () } = {} -- (eventType, key?)

local CooldownClient = {}

local function now(): number
	return os.clock()
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
	return cooldowns[key]
end

function CooldownClient.getRemaining(key: string): number
	local rec = cooldowns[key]
	if not rec then return 0 end
	local rem = rec.endAt - now()
	if rem <= 0 then
		cooldowns[key] = nil
		fire("clear", key)
		return 0
	end
	return rem
end

function CooldownClient.getFraction(key: string): number
	local rec = cooldowns[key]
	if not rec then return 0 end
	if rec.duration <= 0 then return 1 end
	local elapsed = now() - rec.startAt
	return math.clamp(elapsed / rec.duration, 0, 1)
end

function CooldownClient.isOnCooldown(key: string): boolean
	return CooldownClient.getRemaining(key) > 0
end

function CooldownClient.iterate(): { { key: string, remaining: number, fraction: number } }
	local list: { { key: string, remaining: number, fraction: number } } = {}
	for key, rec in pairs(cooldowns) do
		local rem = rec.endAt - now()
		if rem > 0 then
			local frac = 0
			if rec.duration > 0 then
				frac = math.clamp((now() - rec.startAt) / rec.duration, 0, 1)
			else
				frac = 1
			end
			table.insert(list, { key = key, remaining = rem, fraction = frac })
		else
			cooldowns[key] = nil
			fire("clear", key)
		end
	end
	return list
end

function CooldownClient.requestSnapshot()
	if okNet then
		NetRay:Request(SNAPSHOT_REQUEST, {}):catch(function(err)
			warn("CooldownClient: snapshot request failed", err)
		end)
	end
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

-- Event wiring (replaced to include charges)
if okNet then
	NetRay:GetEvent(EVENT_NAME):OnEvent(function(payload)
		local t = payload and payload.t
		if t == "cd_start" then
			local key = payload.key
			if key then
				cooldowns[key] = {
					startAt = payload.startAt or now(),
					endAt = payload.endAt or now(),
					duration = payload.duration or ((payload.endAt or 0) - (payload.startAt or 0)),
					charges = payload.charges and {
						current = payload.charges.current or 0,
						max = payload.charges.max or 0,
						rechargeEnd = payload.charges.rechargeEnd,
						rechargeDuration = payload.charges.rechargeDuration or 0,
					} or nil,
				}
				fire("start", key)
			end
		elseif t == "cd_adjust" then
			local key = payload.key
			local rec = key and cooldowns[key]
			if rec then
				rec.startAt = payload.startAt or rec.startAt
				rec.endAt = payload.endAt or rec.endAt
				rec.duration = payload.duration or rec.duration
				if payload.charges then
					rec.charges = rec.charges or {
						current = 0, max = 0, rechargeEnd = nil, rechargeDuration = 0,
					}
					local ch = rec.charges :: ChargeState
					ch.current = payload.charges.current or ch.current
					ch.max = payload.charges.max or ch.max
					ch.rechargeEnd = payload.charges.rechargeEnd
					ch.rechargeDuration = payload.charges.rechargeDuration or ch.rechargeDuration
				end
				fire("adjust", key)
			end
		elseif t == "cd_update" then
			local key = payload.key
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
					ch.rechargeEnd = chPayload.rechargeEnd
					ch.rechargeDuration = chPayload.rechargeDuration or ch.rechargeDuration
				end
				fire("update", key)
			end
		elseif t == "cd_clear" then
			local key = payload.key
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
					cooldowns[k] = {
						startAt = v.startAt or now(),
						endAt = v.endAt or now(),
						duration = v.duration or ((v.endAt or 0) - (v.startAt or 0)),
						charges = v.charges and {
							current = v.charges.current or 0,
							max = v.charges.max or 0,
							rechargeEnd = v.charges.rechargeEnd,
							rechargeDuration = v.charges.rechargeDuration or 0,
						} or nil,
					}
				end
				fire("snapshot", nil)
			end
		end
	end)
end

return CooldownClient
