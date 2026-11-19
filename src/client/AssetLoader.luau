--!strict
-- Lightweight client asset loader focused on animations. Designed to expand into broader
-- asset preloading as the project grows.
--
-- Animations come from AnimationRegistry: one Animation instance per published clip, named by its
-- full key. In Studio, a declared clip with no published ID can stand in a draft KeyframeSequence
-- mirrored by the server (server/dev/AnimationDrafts), so unpublished clips are playable in a
-- playtest without ever reaching a live server.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")
local AnimationClipProvider = game:GetService("AnimationClipProvider")
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")
local RunService = game:GetService("RunService")

local AnimationRegistry = require(ReplicatedStorage.Shared.Animation.AnimationRegistry)

local AssetLoader = {}

local DRAFTS_FOLDER_NAME = "AnimationDrafts"

local animationRegistry: { [string]: Animation } = {}
local animationLengths: { [string]: number } = {}
local warnedMissing: { [string]: boolean } = {}

local initialized = false
local dummyAnimator: Animator? = nil

local function getDummyAnimator(): Animator
	if dummyAnimator and dummyAnimator.Parent then
		return dummyAnimator
	end
	local controller = Instance.new("AnimationController")
	controller.Name = "AssetLoaderController"
	controller.Parent = script
	local animator = Instance.new("Animator")
	animator.Parent = controller
	dummyAnimator = animator
	return animator
end

local function makeAnimation(key: string, id: string): Animation
	local anim = Instance.new("Animation")
	anim.Name = key
	anim.AnimationId = id
	return anim
end

local function indexAnimations()
	for _, clip in AnimationRegistry.list() do
		if clip.id then
			animationRegistry[clip.key] = makeAnimation(clip.key, clip.id)
		end
	end
end

local function registerDraft(child: Instance)
	if not child:IsA("KeyframeSequence") then
		return
	end
	local kfs = child :: KeyframeSequence
	local clip = AnimationRegistry.get(kfs.Name)
	-- A published ID always wins, so a stale draft left in the place cannot shadow the real clip.
	if not clip or clip.id then
		return
	end
	local ok, tempId = pcall(function()
		return KeyframeSequenceProvider:RegisterKeyframeSequence(kfs)
	end)
	if not ok then
		warn("[AssetLoader] Failed to register draft", kfs.Name, tempId)
		return
	end
	animationRegistry[clip.key] = makeAnimation(clip.key, tempId)
	-- Read straight off the keyframes: a temporary ID's track can report Length 0 until it loads,
	-- and playTimed would then scale the clip to a standstill.
	local length = 0
	for _, keyframe in kfs:GetKeyframes() do
		length = math.max(length, (keyframe :: Keyframe).Time)
	end
	animationLengths[clip.key] = if length > 0 then length else nil
end

local function watchDrafts()
	if not RunService:IsStudio() then
		return
	end
	local function attach(folder: Instance)
		for _, child in folder:GetChildren() do
			registerDraft(child)
		end
		folder.ChildAdded:Connect(registerDraft)
	end
	local existing = ReplicatedStorage:FindFirstChild(DRAFTS_FOLDER_NAME)
	if existing then
		attach(existing)
		return
	end
	local conn: RBXScriptConnection? = nil
	conn = ReplicatedStorage.ChildAdded:Connect(function(child)
		if child.Name == DRAFTS_FOLDER_NAME then
			if conn then
				conn:Disconnect()
			end
			attach(child)
		end
	end)
end

local function tryCaptureWithClipProvider(animation: Animation): number?
	if typeof(animation.AnimationId) ~= "string" or animation.AnimationId == "" then
		return nil
	end
	local ok, clip = pcall(function()
		return AnimationClipProvider:GetAnimationClip(animation.AnimationId)
	end)
	if not ok or not clip then
		return nil
	end
	local length = clip.Length
	if typeof(length) == "number" and length > 0 then
		return length
	end
	return nil
end

local function captureLengthViaAnimator(key: string, animation: Animation): number?
	local animator = getDummyAnimator()
	local ok, trackOrErr = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if not ok then
		warn("[AssetLoader] Failed to load animation", key, trackOrErr)
		return nil
	end
	local track: AnimationTrack = trackOrErr :: AnimationTrack
	local length = track.Length
	if length and length > 0 then
		track:Destroy()
		return length
	end

	local obtained = false
	local connection: RBXScriptConnection? = nil
	connection = track:GetPropertyChangedSignal("Length"):Connect(function()
		if track.Length and track.Length > 0 then
			obtained = true
			if connection then
				connection:Disconnect()
				connection = nil
			end
		end
	end)

	-- Play at zero speed to encourage asset fetch without advancing the timeline.
	local success, playErr = pcall(function()
		track:Play(0)
	end)
	if not success then
		warn("[AssetLoader] Failed to play animation for preload", key, playErr)
	else
		track:AdjustSpeed(0)
	end

	local start = os.clock()
	while os.clock() - start < 2 do
		if track.Length and track.Length > 0 then
			obtained = true
			break
		end
		task.wait()
	end

	track:Stop()
	if connection then
		connection:Disconnect()
	end

	if obtained and track.Length and track.Length > 0 then
		length = track.Length
	end

	track:Destroy()
	return length
end

local function resolveAnimationLength(key: string, animation: Animation): number?
	local length = tryCaptureWithClipProvider(animation)
	if length and length > 0 then
		return length
	end
	return captureLengthViaAnimator(key, animation)
end

local function preloadAnimations()
	local list = {}
	for _, anim in pairs(animationRegistry) do
		table.insert(list, anim)
	end
	if #list == 0 then
		return
	end
	local ok, err = pcall(function()
		ContentProvider:PreloadAsync(list)
	end)
	if not ok then
		warn("[AssetLoader] PreloadAsync failed:", err)
	end
end

function AssetLoader.init()
	if initialized then
		return
	end
	initialized = true
	indexAnimations()
	watchDrafts()

	preloadAnimations()

	for key, anim in pairs(animationRegistry) do
		local length = resolveAnimationLength(key, anim)
		if length and length > 0 then
			animationLengths[key] = length
		end
	end
end

function AssetLoader.getAnimation(name: string): Animation?
	if not initialized then
		AssetLoader.init()
	end
	local anim = animationRegistry[name]
	if anim then
		return anim
	end
	-- Once per key: a missing clip is asked for on every swing.
	if not warnedMissing[name] then
		warnedMissing[name] = true
		if AnimationRegistry.get(name) then
			warn(`[AssetLoader] '{name}' has no published animation yet`)
		else
			warn(`[AssetLoader] '{name}' is not declared by any owner`)
		end
	end
	return nil
end

function AssetLoader.getAnimationLength(name: string): number?
	if not initialized then
		AssetLoader.init()
	end
	local cached = animationLengths[name]
	if cached and cached > 0 then
		return cached
	end
	local anim = animationRegistry[name]
	if not anim then
		return nil
	end
	local resolved = resolveAnimationLength(name, anim)
	if resolved and resolved > 0 then
		animationLengths[name] = resolved
		return resolved
	end
	return nil
end

function AssetLoader.cacheAnimationLength(name: string, length: number)
	if length > 0 then
		animationLengths[name] = length
	end
end

return AssetLoader
