--!strict
-- How fast an entity moves, as multipliers from named sources (a chill, a slow, a passive), so
-- effects that overlap neither fight over Humanoid.WalkSpeed nor restore the wrong value when one
-- ends: the speed is always the entity's own base times every multiplier in force.
--
-- The combined multiplier is kept on the model as `SpeedScale`. NPCs: their Movement component
-- picks walk and run speeds itself and multiplies them by it (`CurrentBaseSpeed` is the speed it
-- last chose). Players: WalkSpeed is set here from the place's character walk speed.

local Players = game:GetService("Players")
local StarterPlayer = game:GetService("StarterPlayer")
local ServerScriptService = game:GetService("ServerScriptService")

local Registrar = require(ServerScriptService.Server.Services.Registrar)

local SpeedModifiers = {}

local bySource: { [string]: { [string]: number } } = {}

local function scaleOf(entityId: string): number
	local scale = 1
	for _, multiplier in pairs(bySource[entityId] or {}) do
		scale *= multiplier
	end
	return math.max(0, scale)
end

local function apply(entityId: string)
	local model = Registrar.getEntityById(entityId)
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	if not model or not humanoid then
		return
	end
	local scale = scaleOf(entityId)
	model:SetAttribute("SpeedScale", scale)
	local base: number
	if Registrar.isPlayerEntity(entityId) then
		base = StarterPlayer.CharacterWalkSpeed
	else
		local current = model:GetAttribute("CurrentBaseSpeed")
		base = if type(current) == "number" then current else humanoid.WalkSpeed
	end
	humanoid.WalkSpeed = base * scale
end

-- Set `source`'s multiplier on `entityId` (0.7 is 30% slower, 1.1 is 10% faster).
function SpeedModifiers.set(entityId: string, source: string, multiplier: number)
	local sources = bySource[entityId]
	if not sources then
		sources = {}
		bySource[entityId] = sources
	end
	if sources[source] == multiplier then
		return
	end
	sources[source] = multiplier
	apply(entityId)
end

function SpeedModifiers.clear(entityId: string, source: string)
	local sources = bySource[entityId]
	if not sources or sources[source] == nil then
		return
	end
	sources[source] = nil
	if next(sources) == nil then
		bySource[entityId] = nil
	end
	apply(entityId)
end

function SpeedModifiers.scaleOf(entityId: string): number
	return scaleOf(entityId)
end

-- A new character's Humanoid starts at the default speed. Status effects that slowed the old one
-- are cleared on respawn and clear their own multipliers; what is left (a passive) applies to the
-- new body.
Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function()
		task.defer(function()
			local entityId = Registrar.getPlayerId(player)
			if entityId and bySource[entityId] then
				apply(entityId)
			end
		end)
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	local entityId = Registrar.getPlayerId(player)
	if entityId then
		bySource[entityId] = nil
	end
end)

return SpeedModifiers
