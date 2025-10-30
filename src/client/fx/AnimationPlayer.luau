-- Thin wrapper over Animator with key registry

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AssetLoader = require(script.Parent.Parent.AssetLoader)

local AnimationPlayer = {}

local AnimationsFolder = ReplicatedStorage:FindFirstChild("Assets")
	and ReplicatedStorage.Assets:FindFirstChild("Animations")
local cache: { [string]: AnimationTrack } = {}
-- local cachedLengths: { [string]: number } = {}

local function getAnimator(): Animator?
	local char = Players.LocalPlayer.Character
	if not char then
		return nil
	end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end
	return humanoid:FindFirstChildOfClass("Animator") or nil
end

local function loadTrack(key: string): AnimationTrack?
	if cache[key] then
		return cache[key]
	end
	if not AnimationsFolder then
		return nil
	end
	local animInstance = AssetLoader.getAnimation(key)
	if not animInstance then
		local fallback = AnimationsFolder and AnimationsFolder:FindFirstChild(key)
		if fallback and fallback:IsA("Animation") then
			animInstance = fallback :: Animation
		else
			return nil
		end
	end
	local anim = animInstance :: Animation
	local animator = getAnimator()
	if not animator then
		return nil
	end
	local track = animator:LoadAnimation(anim)
	local nativeLength = AssetLoader.getAnimationLength(key)
	if nativeLength and nativeLength > 0 then
		track:SetAttribute("NativeLength", nativeLength)
	end
	cache[key] = track
	return track
end

function AnimationPlayer.play(key: string, fade: number?, speed: number?)
	local track = loadTrack(key)
	if not track then
		return
	end
	track:Play(fade or 0.1)
	if speed then
		track:AdjustSpeed(speed)
	end
end

-- Plays and returns the AnimationTrack so callers can bind marker callbacks.
function AnimationPlayer.playReturn(key: string, fade: number?, speed: number?): AnimationTrack?
	local track = loadTrack(key)
	if not track then
		return nil
	end
	track:Play(fade or 0.1)
	if speed then
		track:AdjustSpeed(speed)
	end
	return track
end

export type TimedOptions = {
	fade: number?,
	duration: number,
}

function AnimationPlayer.playTimed(key: string, options: TimedOptions): AnimationTrack?
	local track = loadTrack(key)
	if not track then
		return nil
	end

	local duration = options.duration

	local trackLength = track.Length

	if not track:GetAttribute("NativeLength") then
		local cached = AssetLoader.getAnimationLength(key)
		if cached and cached > 0 then
			trackLength = cached
			track:SetAttribute("NativeLength", cached)
		end
	end

	local speed = trackLength / (duration or trackLength)

	track:Play(options.fade or 0.1)
	if speed then
		track:AdjustSpeed(speed)
	end
	if track.Length and track.Length > 0 then
		AssetLoader.cacheAnimationLength(key, track.Length)
	end

	return track
end

function AnimationPlayer.stop(key: string, fade: number?)
	local track = cache[key]
	if not track then
		return
	end
	track:Stop(fade or 0.1)
end

return AnimationPlayer
