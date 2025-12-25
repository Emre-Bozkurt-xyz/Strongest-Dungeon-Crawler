--!strict
-- StaggerController: Plays stagger animations when server confirms stagger applied

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Networking = require(ReplicatedStorage.Shared.Networking)
local ClientRegistrar = require(script.Parent.Parent.Parent.ClientRegistrar)
local CharacterSpecRegistry = require(ReplicatedStorage.Shared.Characters.CharacterSpecRegistry)
local ImmediateHitFeedback = require(script.Parent.Parent.Parent.fx.ImmediateHitFeedback)

local StaggerController = {}

local DEBUG = false
local localPlayer = Players.LocalPlayer

-- Resolve the character spec ID for an entity
local function resolveSpecId(model: Model, entityId: string): string
	-- Check if it's a player character
	if ClientRegistrar.isPlayerEntity(entityId) then
		return "PlayerCharacter"
	end

	-- For NPCs, prefer the CharacterSpecId attribute (set during spawn)
	-- Falls back to model name for backwards compatibility
	local specId = model:GetAttribute("CharacterSpecId")
	if specId and type(specId) == "string" then
		return specId
	end

	return model.Name
end

-- Pick a random animation ID from a field that can be string or array
local function pickAnimation(animField: (string | { string })?): string?
	if not animField then
		return nil
	end

	if type(animField) == "string" then
		return animField
	elseif type(animField) == "table" then
		local list = animField :: { string }
		if #list == 0 then
			return nil
		elseif #list == 1 then
			return list[1]
		else
			return list[math.random(1, #list)]
		end
	end

	return nil
end

-- Play stagger animation on a model
local function playStaggerAnimation(model: Model, targetId: string)
	local humanoid = model:FindFirstChild("Humanoid") :: Humanoid?
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end

	local animator = humanoid:FindFirstChild("Animator") :: Animator?
	if not animator then
		return
	end

	-- Resolve the correct spec for this entity
	local specId = resolveSpecId(model, targetId)
	local spec = CharacterSpecRegistry.get(specId)

	if not spec or not spec.animations or not spec.animations.stagger then
		if DEBUG then
			warn(`[Stagger] No stagger animation configured for {targetId} (spec: {specId})`)
		end
		return
	end

	-- Pick random animation if array provided
	local animId = pickAnimation(spec.animations.stagger)
	if not animId then
		if DEBUG then
			warn(`[Stagger] Empty stagger animation list for {targetId} (spec: {specId})`)
		end
		return
	end

	local anim = Instance.new("Animation")
	anim.AnimationId = animId
	local animTrack = animator:LoadAnimation(anim)
	animTrack:Play()
	anim:Destroy()

	if DEBUG then
		print(`[Stagger] Playing stagger animation for {targetId} (spec: {specId})`)
	end
end

-- Find character model from entityId
local function findCharacter(entityId: string): Model?
	local entity = ClientRegistrar.getEntity(entityId)
	if not entity then
		return nil
	end

	if entity:IsA("Model") and entity:FindFirstChild("HumanoidRootPart") then
		return entity
	end

	local parent = entity.Parent
	if parent and parent:IsA("Model") and parent:FindFirstChild("HumanoidRootPart") then
		return parent
	end

	return nil
end

-- Check if entityId is the local player
local function isLocalPlayer(entityId: string): boolean
	if not localPlayer or not localPlayer.Character then
		return false
	end
	local localEntityId = localPlayer.Character:GetAttribute("EntityId")
	return localEntityId == entityId
end

function StaggerController.init()
	local dispatcher = Networking.client()

	dispatcher:on("HitEvent", function(event)
		local character = findCharacter(event.targetId)
		if not character then
			return
		end

		-- Flash local player when THEY are hit (victim feedback)
		-- This is the only place we need server-authoritative flash - attacker sees
		-- immediate flash via animation markers, but victim needs server confirmation
		if isLocalPlayer(event.targetId) and event.result.totalDamage > 0 then
			ImmediateHitFeedback.flashTarget(character, event.result.crit)
			if DEBUG then
				print(`[Stagger] Local player hit - flashing`)
			end
		end

		-- Play stagger animation if stagger was applied
		if event.result.staggerApplied then
			playStaggerAnimation(character, event.targetId)
		end
	end)

	if DEBUG then
		print("[Stagger] Initialized")
	end
end

return StaggerController
