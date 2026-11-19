--!strict
-- Pool values for dev tooling: setting a pool outright, and holding one at a value.
--
-- A hold pins a pool where it is until it is released: whatever moves it -- a hit, a skill's cost,
-- regeneration, a rebuild that refills every pool -- it is put straight back. It is session tooling,
-- not part of a character: no spec or save holds it, and going back to the real save releases every
-- hold.
--
-- Discrete writes (damage, costs, the refill of a rebuild) are undone in the same call that made
-- them, through StatsManager.onPoolChanged, so a lethal hit on held Health lands -- damage number,
-- hit reaction, XP for the attacker -- but Health is back at the held value before the hit returns
-- and never rests at zero. Regeneration writes pools without reporting it, so it is undone on the
-- next frame instead.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Server = ServerScriptService.Server
local Registrar = require(Server.Services.Registrar)
local StatsManager = require(Server.Stats.StatsManager)

local EPSILON = 1e-3

local Holds = {}

-- Player -> pool -> held value (absolute).
local holds: { [Player]: { [string]: number } } = {}
local started = false

-- `value` as an absolute amount for a pool whose maximum is `max`: a fraction of it when <= 1 (the
-- spec's rule), an amount above that, clamped to the pool.
function Holds.resolve(value: number, max: number): number
	local target = if value <= 1 then max * value else value
	return math.clamp(target, 0, max)
end

-- Puts the pool at exactly `target`. Both directions go through addToPool: removeFromPool runs the
-- cost pipeline, which may redirect or scale the amount, and a set is not a cost.
local function write(entityId: string, pool: string, target: number)
	local current = StatsManager.getPoolCurrentValue(entityId, pool :: any)
	if current and math.abs(current - target) > EPSILON then
		StatsManager.addToPool(entityId, pool :: any, target - current)
	end
end

-- Sets a pool to `value` (a fraction of its maximum when <= 1, else an amount). A held pool is held
-- at the new value. Returns the value set, or nil when the player has no such pool.
function Holds.setPool(player: Player, pool: string, value: number): number?
	local entityId = Registrar.getPlayerId(player)
	local max = entityId and StatsManager.getPoolMaxValue(entityId, pool :: any)
	if not entityId or not max then
		return nil
	end
	local target = Holds.resolve(value, max)
	local held = holds[player]
	if held and held[pool] then
		held[pool] = target
	end
	write(entityId, pool, target)
	return target
end

-- Holds a pool at its current value, or releases it. Returns the held value, nil when released or
-- when the player has no such pool.
function Holds.hold(player: Player, pool: string, on: boolean): number?
	local entityId = Registrar.getPlayerId(player)
	local current = entityId and StatsManager.getPoolCurrentValue(entityId, pool :: any)
	if not on or not current then
		local held = holds[player]
		if held then
			held[pool] = nil
			if next(held) == nil then
				holds[player] = nil
			end
		end
		return nil
	end
	local held = holds[player] or {}
	holds[player] = held
	held[pool] = current
	return current
end

function Holds.heldOf(player: Player): { [string]: number }
	return table.clone(holds[player] or {})
end

function Holds.releaseAll(player: Player)
	holds[player] = nil
end

-- Puts every held pool of the player back at its value (after a rebuild refilled them).
function Holds.reapply(player: Player)
	local held = holds[player]
	local entityId = Registrar.getPlayerId(player)
	if not held or not entityId then
		return
	end
	for pool, value in pairs(held) do
		local max = StatsManager.getPoolMaxValue(entityId, pool :: any)
		if max then
			write(entityId, pool, math.min(value, max))
		end
	end
end

local function enforce(entityId: string, pool: string)
	local player = Registrar.getPlayerById(entityId)
	local held = player and holds[player]
	local value = held and held[pool]
	if not value then
		return
	end
	local max = StatsManager.getPoolMaxValue(entityId, pool :: any)
	if max then
		write(entityId, pool, math.min(value, max))
	end
end

function Holds.start()
	if started then
		return
	end
	started = true
	StatsManager.onPoolChanged(enforce)
	RunService.Heartbeat:Connect(function()
		for player, held in pairs(holds) do
			local entityId = Registrar.getPlayerId(player)
			if entityId then
				for pool in pairs(held) do
					enforce(entityId, pool)
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		holds[player] = nil
	end)
end

return Holds
