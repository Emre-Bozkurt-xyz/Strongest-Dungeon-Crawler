--!strict
-- Per-player skill cooldowns (and optional GCD)

local Players = game:GetService("Players")

local CooldownService = {}

local skillCD: { [Player]: { [string]: number } } = {}
local gcdEnd: { [Player]: number } = {}
local DEFAULT_GCD = 1.0

local function now(): number
	return tick()
end

local function ensure(player: Player)
	skillCD[player] = skillCD[player] or {}
	gcdEnd[player] = gcdEnd[player] or 0
end

function CooldownService.isOnCooldown(player: Player, key: string): (boolean, number)
	ensure(player)
	local t = now()
	local endAt = skillCD[player][key]
	local g = gcdEnd[player]
	local remaining = 0
	if endAt and endAt > t then
		remaining = endAt - t
		return true, remaining
	end
	if g and g > t then
		remaining = g - t
		return true, remaining
	end
	return false, 0
end

function CooldownService.start(player: Player, key: string, duration: number)
	ensure(player)
	skillCD[player][key] = now() + math.max(0, duration)
end

function CooldownService.startGCD(player: Player, duration: number?)
	ensure(player)
	gcdEnd[player] = now() + (duration or DEFAULT_GCD)
end

function CooldownService.getRemaining(player: Player, key: string): number
	ensure(player)
	local t = now()
	local endAt = skillCD[player][key]
	return math.max(0, (endAt or 0) - t)
end

function CooldownService.getGCDRemaining(player: Player): number
	ensure(player)
	return math.max(0, (gcdEnd[player] or 0) - now())
end

local function cleanup(player: Player)
	skillCD[player] = nil
	gcdEnd[player] = nil
end

Players.PlayerRemoving:Connect(cleanup)

return CooldownService
