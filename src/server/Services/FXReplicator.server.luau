local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Networking = require(ReplicatedStorage.Shared.Networking)
local Entities = require(ReplicatedStorage.Shared.Utils.Entities)

local dispatcher = Networking.server()
dispatcher:_ensureChannel("FX")

export type FXEventOptions = {
	entityId: string,
	fxKey: string,
	origin: Vector3?,
	range: number?,
	anchorName: string?,
	offset: CFrame?,
	lifetime: number?,
	action: string?,
	step: number?, -- Combo step for proper FX keying
	meta: { [string]: any }?,
}

local function findAllPlayersInRange(position: Vector3, range: number)
	local playersInRange = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
			local distance = (player.Character.HumanoidRootPart.Position - position).Magnitude
			if distance <= range then
				table.insert(playersInRange, player)
			end
		end
	end
	return playersInRange
end

local function findEntityPosition(entityId: string): Vector3
	local entity = Entities.getEntityById(entityId)
	if entity and entity.PrimaryPart then
		return entity.PrimaryPart.Position
	end

	return Vector3.zero
end

dispatcher:on("FXEvent", function(payload: FXEventOptions, meta: any)
	-- Server relay: broadcast to other players in range, EXCLUDING sender to prevent echo-back
	local sender = meta.player
	local targets = findAllPlayersInRange(payload.origin or findEntityPosition(payload.entityId), payload.range or 50)

	dispatcher:emit("FXEvent", payload, {
		targets = targets,
		exclude = sender, -- Critical: don't send back to the client that triggered it
	})
end)
