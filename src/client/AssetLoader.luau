--!strict
-- Lightweight client asset loader focused on animations. Designed to expand into broader
-- asset preloading as the project grows.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")
local AnimationClipProvider = game:GetService("AnimationClipProvider")

local AssetLoader = {}

local AssetsFolder = ReplicatedStorage:FindFirstChild("Assets")
local AnimationsFolder = AssetsFolder and AssetsFolder:FindFirstChild("Animations")

local animationRegistry: { [string]: Animation } = {}
local animationLengths: { [string]: number } = {}

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

local function registerAnimationInstance(anim: Animation)
	animationRegistry[anim.Name] = anim
end

local function indexAnimations()
	if not AnimationsFolder then
		return
	end
	for _, child in ipairs(AnimationsFolder:GetChildren()) do
		if child:IsA("Animation") then
			registerAnimationInstance(child)
		end
	end
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

	if AnimationsFolder then
		AnimationsFolder.ChildAdded:Connect(function(child)
			if child:IsA("Animation") then
				registerAnimationInstance(child)
				animationLengths[child.Name] = nil
			end
		end)
		AnimationsFolder.ChildRemoved:Connect(function(child)
			if child:IsA("Animation") then
				animationRegistry[child.Name] = nil
				animationLengths[child.Name] = nil
			end
		end)
	end

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
	if AnimationsFolder then
		local found = AnimationsFolder:FindFirstChild(name)
		if found and found:IsA("Animation") then
			registerAnimationInstance(found)
			return found
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
	local anim = AssetLoader.getAnimation(name)
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
