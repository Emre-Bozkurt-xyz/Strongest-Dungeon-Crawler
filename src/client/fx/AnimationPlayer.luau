--!strict
-- Thin wrapper over Animator with key registry

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnimationPlayer = {}

local AnimationsFolder = ReplicatedStorage:FindFirstChild("Assets")
	and ReplicatedStorage.Assets:FindFirstChild("Animations")
local cache: { [string]: AnimationTrack } = {}

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
	local anim = AnimationsFolder:FindFirstChild(key)
	if not anim or not anim:IsA("Animation") then
		return nil
	end
	local animator = getAnimator()
	if not animator then
		return nil
	end
	local track = animator:LoadAnimation(anim)
	cache[key] = track
	return track
end

function AnimationPlayer.play(key: string, fade: number?, speed: number?)
	local track = loadTrack(key)
	if not track then
		return
	end
	if speed then
		track:AdjustSpeed(speed)
	end
	track:Play(fade or 0.1)
end

function AnimationPlayer.stop(key: string, fade: number?)
	local track = cache[key]
	if not track then
		return
	end
	track:Stop(fade or 0.1)
end

return AnimationPlayer
