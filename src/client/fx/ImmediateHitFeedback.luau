--!strict
-- ImmediateHitFeedback: Client-side immediate feedback for hits
-- Plays flash, sound, camera shake on animation markers WITHOUT waiting for server
-- Server HitEvent is only used for damage numbers and authoritative stagger

local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local ClientHitDetection = require(script.Parent.ClientHitDetection)
local Replicator = require(script.Parent.Replicator)

local ImmediateHitFeedback = {}

-- Configuration
local FLASH_DURATION = 0.1
local FLASH_INTENSITY = 0.7
local CRIT_FLASH_INTENSITY = 1.0

-- Default hit sounds (can be overridden per skill)
local DEFAULT_HIT_SOUNDS = {
	"rbxassetid://9117969584", -- Generic impact
}

-- Default cast sounds
local DEFAULT_CAST_SOUNDS = {
	"rbxassetid://9114906070", -- Whoosh
}

-- Flash a model with a Highlight effect
local function flashModel(model: Model, isCrit: boolean?)
	if not model or not model:IsA("Model") then
		return
	end

	local intensity = (isCrit and CRIT_FLASH_INTENSITY) or FLASH_INTENSITY
	local flashColor = isCrit and Color3.fromRGB(255, 200, 50) or Color3.fromRGB(255, 255, 255)

	local highlight = Instance.new("Highlight")
	highlight.FillColor = flashColor
	highlight.FillTransparency = 1 - intensity
	highlight.OutlineTransparency = 1
	highlight.Parent = model

	-- Fade out
	local tween = TweenService:Create(
		highlight,
		TweenInfo.new(FLASH_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ FillTransparency = 1 }
	)
	tween:Play()

	tween.Completed:Connect(function()
		highlight:Destroy()
	end)
end

-- Get character position
local function getCharacterPosition(): Vector3?
	local char = Players.LocalPlayer and Players.LocalPlayer.Character
	if not char then
		return nil
	end
	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	return hrp and hrp.Position
end

-- Pick a random sound from a list
local function pickRandomSound(sounds: { string }?): string?
	if not sounds or #sounds == 0 then
		return nil
	end
	return sounds[math.random(1, #sounds)]
end

export type HitFeedbackOptions = {
	-- Detection options
	origin: CFrame?, -- Override origin (defaults to character)
	coneAngle: number?, -- Cone angle in degrees
	coneRange: number?, -- Cone range in studs

	-- Feedback options
	hitSounds: { string }?, -- Array of hit sound IDs to choose from
	flashTargets: boolean?, -- Whether to flash hit targets (default true)

	-- Replication
	replicateSound: boolean?, -- Replicate sound to other players (default true)
}

export type CastSoundOptions = {
	castSounds: { string }?, -- Array of cast sound IDs
	position: Vector3?, -- Position to play at (defaults to character)
	replicateSound: boolean?, -- Replicate to other players (default true)
}

-- Play immediate hit feedback on an animation marker
-- This does client-side hit detection and plays flash/sound/shake
function ImmediateHitFeedback.onImpactMarker(opts: HitFeedbackOptions?)
	local options: HitFeedbackOptions = opts or {} :: HitFeedbackOptions

	-- Perform client-side hit detection
	local result = ClientHitDetection.queryCone({
		origin = options.origin,
		angleDeg = options.coneAngle,
		range = options.coneRange,
	})

	if not result.hit then
		-- No targets detected - still play a "whiff" sound?
		-- For now, just skip feedback
		return
	end

	-- Flash targets
	local shouldFlash = options.flashTargets ~= false -- default true
	if shouldFlash then
		for _, target in ipairs(result.targets) do
			flashModel(target, false)
		end
	end

	-- Play hit sound at primary target position
	local hitSounds = options.hitSounds or DEFAULT_HIT_SOUNDS
	local soundId = pickRandomSound(hitSounds)
	if soundId and result.position then
		Replicator.playSoundAt(soundId, result.position)

		-- Replicate to other players
		local shouldReplicate = options.replicateSound ~= false
		if shouldReplicate then
			Replicator.emitSFX({
				soundId = soundId,
				position = result.position,
			})
		end
	end
end

-- Play immediate cast sound when skill starts
function ImmediateHitFeedback.onCastStart(opts: CastSoundOptions?): BasePart?
	local options: CastSoundOptions = opts or {} :: CastSoundOptions

	local castSounds = options.castSounds or DEFAULT_CAST_SOUNDS
	local soundId = pickRandomSound(castSounds)

	if not soundId then
		return
	end

	-- Get position
	local position = options.position or getCharacterPosition()
	if not position then
		return
	end

	-- Play locally
	local soundPart = Replicator.playSoundAt(soundId, position)

	-- Replicate to other players
	local shouldReplicate = options.replicateSound ~= false
	if shouldReplicate then
		Replicator.emitSFX({
			soundId = soundId,
			position = position,
		})
	end

	return soundPart
end

-- Flash a specific model (for use when we know the target, e.g., from HitEvent)
function ImmediateHitFeedback.flashTarget(target: Model, isCrit: boolean?)
	flashModel(target, isCrit)
end

-- Play hit sound at a specific position
function ImmediateHitFeedback.playHitSound(position: Vector3, sounds: { string }?, replicate: boolean?)
	local soundId = pickRandomSound(sounds or DEFAULT_HIT_SOUNDS)
	if soundId then
		Replicator.playSoundAt(soundId, position)
		if replicate ~= false then
			Replicator.emitSFX({ soundId = soundId, position = position })
		end
	end
end

return ImmediateHitFeedback
