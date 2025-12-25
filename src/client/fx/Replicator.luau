local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Entities = require(ReplicatedStorage.Shared.Utils.Entities)
local Networking = require(ReplicatedStorage.Shared.Networking)
local FXPlayer = require(script.Parent.FXPlayer)
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")

local dispatcher = Networking.client()
dispatcher:_ensureChannel("FX")

local Replicator = {}

-- Store FX handles with metadata for attempt-based cleanup
-- fxMap[entityId][fxKey] = { handle: FXHandle, attemptId: string?, skillName: string? }
local fxMap: { [string]: { [string]: { handle: any, attemptId: string?, skillName: string? } } } = {}

-- Sound configuration
local SFX_DEFAULT_VOLUME = 0.5
local SFX_ROLLOFF_MIN = 10
local SFX_ROLLOFF_MAX = 100

--  Note:   server can provide an entityId if it wishes to attach FX to an entity,
--          else entityId will become "Server", anchoring is not possible here.

export type FXEventOptions = {
	fxKey: string,
	entityId: string?,
	origin: Vector3?,
	range: number?,
	anchorName: string?,
	offset: CFrame?,
	lifetime: number?,
	action: string?,
	step: number?, -- Combo step for proper FX keying
	meta: { [string]: any }?,
}

export type SFXEventOptions = {
	soundId: string,
	entityId: string?,
	anchorName: string?,
	position: Vector3?,
	volume: number?,
	pitch: number?,
	meta: { [string]: any }?,
}

function Replicator.emitFX(opts: FXEventOptions)
	opts.entityId = Players.LocalPlayer.Character:GetAttribute("EntityId")
	if not opts.entityId then
		warn("FXReplicator: Player character does not have an EntityId attribute.")
		return
	end
	dispatcher:emit("FXEvent", opts)
end

-- Emit a sound event for replication to other players
function Replicator.emitSFX(opts: SFXEventOptions)
	opts.entityId = Players.LocalPlayer.Character and Players.LocalPlayer.Character:GetAttribute("EntityId")
	if not opts.entityId then
		warn("Replicator.emitSFX: Player character does not have an EntityId attribute.")
		return
	end
	dispatcher:emit("SFXEvent", opts)
end

-- Play a sound locally at a position (utility for immediate local playback)
function Replicator.playSoundAt(soundId: string, position: Vector3, volume: number?, pitch: number?): BasePart?
	if not soundId or soundId == "" then
		return
	end

	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume or SFX_DEFAULT_VOLUME
	sound.PlaybackSpeed = pitch or 1
	sound.RollOffMaxDistance = SFX_ROLLOFF_MAX
	sound.RollOffMinDistance = SFX_ROLLOFF_MIN

	-- Anchor sound at position for 3D spatial audio
	local soundPart = Instance.new("Part")
	soundPart.Transparency = 1
	soundPart.CanCollide = false
	soundPart.Anchored = true
	soundPart.Size = Vector3.new(0.1, 0.1, 0.1)
	soundPart.Position = position
	soundPart.Parent = workspace

	sound.Parent = soundPart
	sound:Play()

	-- Cleanup after sound finishes
	Debris:AddItem(soundPart, sound.TimeLength + 0.5)
	return soundPart
end

-- Play a sound locally attached to an entity's anchor
function Replicator.playSoundAttached(
	soundId: string,
	entity: Model,
	anchorName: string?,
	volume: number?,
	pitch: number?
)
	if not soundId or soundId == "" or not entity then
		return
	end

	local anchor = anchorName and entity:FindFirstChild(anchorName, true)
	local position: Vector3

	if anchor and anchor:IsA("Attachment") then
		position = anchor.WorldPosition
	elseif anchor and anchor:IsA("BasePart") then
		position = anchor.Position
	else
		local hrp = entity:FindFirstChild("HumanoidRootPart") :: BasePart?
		position = hrp and hrp.Position or entity:GetPivot().Position
	end

	Replicator.playSoundAt(soundId, position, volume, pitch)
end

local findAnchor = function(entity: Model, anchorName: string): Attachment?
	local anchor = entity:FindFirstChild(anchorName, true)
	return anchor
end

dispatcher:on("FXEvent", function(payload: FXEventOptions, _meta: any)
	local fxKey = payload.fxKey
	local step = payload.step

	-- Create step-aware map key (same as BaseSkill)
	local mapKey = if step then `{fxKey}_step{step}` else fxKey

	local entityId = payload.entityId
	local entity = entityId and Entities.getEntityById(entityId) or nil

	if not entityId then
		-- Server event
		entityId = "Server"
		return
	end

	-- CRITICAL: Skip FX for local player's own entity (already spawned locally in BaseSkill)
	local localPlayerEntityId = Players.LocalPlayer.Character and Players.LocalPlayer.Character:GetAttribute("EntityId")
	if entityId == localPlayerEntityId then
		return
	end

	if entityId ~= "Server" and payload.anchorName then
		if payload.action == "start" then
			fxMap[entityId] = fxMap[entityId] or {}

			-- Stop existing FX with same map key (step-aware)
			if fxMap[entityId][mapKey] then
				pcall(fxMap[entityId][mapKey].handle.Stop)
			end

			local anchor = findAnchor(entity, payload.anchorName)
			if anchor then
				local handler = FXPlayer.spawnAttached(fxKey, anchor, payload.offset)
				fxMap[entityId][mapKey] = {
					handle = handler,
					attemptId = payload.meta and payload.meta.attemptId or nil,
					skillName = payload.meta and payload.meta.skillName or nil,
				}
			end
		elseif payload.action == "stop" then
			if fxMap[entityId] and fxMap[entityId][mapKey] then
				pcall(fxMap[entityId][mapKey].handle.Stop)
				fxMap[entityId][mapKey] = nil
			end
		else
			-- One-shot FX
			local anchor = findAnchor(entity, payload.anchorName)
			if anchor then
				FXPlayer.playAttached(fxKey, anchor, payload.offset, payload.lifetime)
			end
		end
	else
		-- World-space FX (no anchor)
		if payload.action == "start" then
			fxMap[entityId] = fxMap[entityId] or {}

			if fxMap[entityId][mapKey] then
				pcall(fxMap[entityId][mapKey].handle.Stop)
			end

			local handler = FXPlayer.spawnAt(fxKey, payload.offset or CFrame.new())
			fxMap[entityId][mapKey] = {
				handle = handler,
				attemptId = payload.meta and payload.meta.attemptId or nil,
				skillName = payload.meta and payload.meta.skillName or nil,
			}
		elseif payload.action == "stop" then
			if fxMap[entityId] and fxMap[entityId][mapKey] then
				pcall(fxMap[entityId][mapKey].handle.Stop)
				fxMap[entityId][mapKey] = nil
			end
		else
			FXPlayer.playAt(fxKey, payload.offset or CFrame.new(), payload.lifetime)
		end
	end
end)

-- Handle SFX events from other players (sound replication)
dispatcher:on("SFXEvent", function(payload: SFXEventOptions, _meta: any)
	local entityId = payload.entityId

	-- Skip for local player (already played locally)
	local localPlayerEntityId = Players.LocalPlayer.Character and Players.LocalPlayer.Character:GetAttribute("EntityId")
	if entityId == localPlayerEntityId then
		return
	end

	-- Get position from payload or entity
	local position = payload.position
	if not position and entityId then
		local entity = Entities.getEntityById(entityId)
		if entity then
			if payload.anchorName then
				local anchor = entity:FindFirstChild(payload.anchorName, true)
				if anchor and anchor:IsA("Attachment") then
					position = anchor.WorldPosition
				elseif anchor and anchor:IsA("BasePart") then
					position = anchor.Position
				end
			end
			if not position then
				local hrp = entity:FindFirstChild("HumanoidRootPart") :: BasePart?
				position = hrp and hrp.Position or entity:GetPivot().Position
			end
		end
	end

	if position then
		Replicator.playSoundAt(payload.soundId, position, payload.volume, payload.pitch)
	end
end)

-- Cleanup helpers for attempt-based FX coordination

-- Stop all FX for a specific entity and skill (useful when skill completes/rejects)
function Replicator.stopAllForSkill(entityId: string, skillName: string)
	if not fxMap[entityId] then
		return
	end
	for mapKey, entry in pairs(fxMap[entityId]) do
		if entry.skillName == skillName then
			pcall(entry.handle.Stop)
			fxMap[entityId][mapKey] = nil
		end
	end
end

-- Stop all FX for a specific attempt ID (most precise cleanup)
function Replicator.stopAllForAttempt(entityId: string, attemptId: string)
	if not fxMap[entityId] then
		return
	end
	for mapKey, entry in pairs(fxMap[entityId]) do
		if entry.attemptId == attemptId then
			pcall(entry.handle.Stop)
			fxMap[entityId][mapKey] = nil
		end
	end
end

-- Stop all FX for an entity (cleanup when entity removed/destroyed)
function Replicator.stopAllForEntity(entityId: string)
	if not fxMap[entityId] then
		return
	end
	for _, entry in pairs(fxMap[entityId]) do
		pcall(entry.handle.Stop)
	end
	fxMap[entityId] = nil
end

return Replicator
