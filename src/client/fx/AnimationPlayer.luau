--!strict
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

function AnimationPlayer.playTimed(key: string, options: { [string]: any }?): AnimationTrack?
	local track = loadTrack(key)
	if not track then
		return nil
	end

	local opts = options or ({} :: { [string]: any })
	local fade = if typeof(opts.fade) == "number" then opts.fade else nil
	local tempo = if typeof(opts.tempo) == "number" and opts.tempo > 0 then opts.tempo else nil
	local durationScale = if typeof(opts.durationScale) == "number" and opts.durationScale > 0 then opts.durationScale else nil
	local baseDuration = if typeof(opts.baseDuration) == "number" and opts.baseDuration > 0 then opts.baseDuration else nil
	local targetDuration = if typeof(opts.targetDuration) == "number" and opts.targetDuration > 0 then opts.targetDuration else nil
	local speed = if typeof(opts.speed) == "number" and opts.speed > 0 then opts.speed else nil

	local trackLength = track.Length
	if (not baseDuration or baseDuration <= 0) and trackLength and trackLength > 0 then
		baseDuration = trackLength
	end
	if not baseDuration or baseDuration <= 0 then
		local attrLength = track:GetAttribute("NativeLength")
		if typeof(attrLength) == "number" and attrLength > 0 then
			baseDuration = attrLength
		else
			local cached = AssetLoader.getAnimationLength(key)
			if cached and cached > 0 then
				baseDuration = cached
				track:SetAttribute("NativeLength", cached)
			end
		end
	end

	if not targetDuration then
		local scale = durationScale
		if not scale and tempo then
			scale = 1 / tempo
		end
		if baseDuration and baseDuration > 0 and scale and scale > 0 then
			targetDuration = baseDuration * scale
		end
	end

	local durationBasis = nil
	if trackLength and trackLength > 0 then
		durationBasis = trackLength
	elseif baseDuration and baseDuration > 0 then
		durationBasis = baseDuration
	end

	if targetDuration and targetDuration > 0 and durationBasis and durationBasis > 0 then
		speed = durationBasis / targetDuration
	end

	if not speed then
		if tempo then
			speed = tempo
		elseif durationScale then
			speed = 1 / durationScale
		end
	end

	track:Play(fade or 0.1)
	if speed then
		track:AdjustSpeed(speed)
	end
	if track.Length and track.Length > 0 then
		AssetLoader.cacheAnimationLength(key, track.Length)
	end

	print("Playing animation:", key, "with speed:", speed)
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
