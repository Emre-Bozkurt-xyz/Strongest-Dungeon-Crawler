--!strict
-- SkillSlotUI: Renders skill slots with draining cooldown overlay + desaturation + charges support.
-- Structure (created dynamically under a ScreenGui you provide or we create lazily):
-- SkillSlots (Frame)
--   UIListLayout
--   SkillSlotContainer (TextButton)
--     Content (Frame)
--       UIPadding
--       Icon (ImageLabel)
--       Timer (TextLabel)
--       Charges (TextLabel)
--     Overlay (Frame)  -- black mask that shrinks downward (Size.Y = remaining/total)
--     GCDOverlay (Frame) -- faint mask for GCD only (independent; more transparent)
--
-- Public API:
--   SkillSlotUI.mount(parentGui: Instance) -> () cleanup
--   SkillSlotUI.setIconProvider(fn: (skillName: string) -> string? )
--   SkillSlotUI.setSlotOrder(indices: {number}) -- optional manual ordering override
--
-- Behaviour:
--   - Only renders filled slots for active profile.
--   - Rebuilds when profile changes or slots change.
--   - Updates cooldown overlay ~10Hz (faster <0.5s remaining).
--   - Desaturates icon (ImageColor3 darker + ImageTransparency tweak) while skill on cooldown OR no charges.
--   - Charges shown bottom-right if >1. Hidden otherwise.
--   - GCD overlay uses lower opacity and never desaturates icons.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ClientSpec = require(ReplicatedStorage.Shared.skills.ClientSpec)

local SkillSlots = require(script.Parent.SkillSlots)
local CooldownClient = require(script.Parent.CooldownClient)

local SkillSlotUI = {}

-- Configuration knobs
local UPDATE_HZ = 10 -- normal update frequency
local FAST_THRESHOLD = 0.5 -- seconds; below this we update every frame
local NORMAL_INTERVAL = 1 / UPDATE_HZ

local OVERLAY_TRANSPARENCY = 0.42
local GCD_OVERLAY_TRANSPARENCY = 0.7
local DESAT_COLOR = Color3.fromRGB(180,180,180) -- simple desaturation by tinting
local READY_COLOR = Color3.fromRGB(255,255,255)
-- Cooldowns shorter than this (seconds) are treated as negligible for per-skill overlay & desaturation
-- to avoid constant flicker on combo step pacing.
local MIN_VISUAL_DURATION = 0.33

local iconProvider: ((string) -> string?)? = nil
local manualOrder: {number}? = nil

-- Internal state
local rootFrame: Frame? = nil
local containerMap: { [number]: TextButton } = {} -- slotIndex -> SkillSlotContainer
local slotSkillMap: { [number]: string } = {} -- slotIndex -> skillName
local slotConnections: { [number]: RBXScriptConnection } = {} -- slotIndex -> Activated connection
local connCleanup: { () -> () } = {}
local updating = false

local function clearConnections()
	for _, c in ipairs(connCleanup) do
		pcall(c)
	end
	connCleanup = {}
end

function SkillSlotUI.setIconProvider(fn: (string) -> string?)
	iconProvider = fn
	if rootFrame then
		-- refresh icons immediately
		SkillSlotUI._rebuild()
	end
end

function SkillSlotUI.setSlotOrder(indices: {number})
	manualOrder = indices
	-- force rebuild
	if rootFrame then
		SkillSlotUI._rebuild()
	end
end

local function getIcon(skill: string): string
	-- Priority: custom provider > ClientSpec icon > placeholder
	if iconProvider then
		local ok, result = pcall(iconProvider, skill)
		if ok and type(result) == "string" and result ~= "" then
			return result
		end
	end
	local spec = ClientSpec[skill]
	if spec and type(spec) == "table" and type(spec.icon) == "string" and spec.icon ~= "" then
		return spec.icon
	end
	return "rbxassetid://0"
end

local function destroyChildren(parent: Instance)
	for _, child in ipairs(parent:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function findTemplate(): TextButton?
	-- Try ReplicatedStorage.Assets.GUI.SkillSlotContainer first; fallback: StarterGui.Assets.GUI
	local template: Instance? = nil
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if assets then
		local guiFolder = assets:FindFirstChild("GUI")
		if guiFolder then
			template = guiFolder:FindFirstChild("SkillSlotContainer")
		end
	end
	if not template then
		local sg = game:GetService("StarterGui"):FindFirstChild("Assets")
		if sg then
			local guiFolder = sg:FindFirstChild("GUI")
			if guiFolder then
				template = guiFolder:FindFirstChild("SkillSlotContainer")
			end
		end
	end
	if template and template:IsA("TextButton") then
		return template
	end
	return nil
end

local cachedTemplate: TextButton? = nil

local function ensureSubLabels(container: TextButton)
	local content = container:FindFirstChild("Content")
	if not content or not content:IsA("Frame") then return end
	local icon = content:FindFirstChild("Icon")
	if not (icon and icon:IsA("ImageLabel")) then
		local newIcon = Instance.new("ImageLabel")
		newIcon.Name = "Icon"
		newIcon.BackgroundTransparency = 1
		newIcon.Size = UDim2.fromScale(1,1)
		newIcon.Parent = content
	end
	if not content:FindFirstChild("Timer") then
		local timer = Instance.new("TextLabel")
		timer.Name = "Timer"
		timer.Size = UDim2.fromScale(1,1)
		timer.BackgroundTransparency = 1
		timer.TextColor3 = Color3.new(1,1,1)
		timer.TextStrokeTransparency = 0.5
		timer.TextScaled = true
		timer.Visible = false
		local limit = Instance.new("UITextSizeConstraint")
		limit.MaxTextSize = 24
		limit.Parent = timer
		timer.Parent = content
	end
	if not content:FindFirstChild("Charges") then
		local charges = Instance.new("TextLabel")
		charges.Name = "Charges"
		charges.AnchorPoint = Vector2.new(1,1)
		charges.Position = UDim2.fromScale(1,1)
		charges.Size = UDim2.fromOffset(24,20)
		charges.BackgroundTransparency = 1
		charges.TextColor3 = Color3.fromRGB(255,255,160)
		charges.TextStrokeTransparency = 0.5
		charges.TextScaled = true
		charges.Visible = false
		local ct = Instance.new("UITextSizeConstraint")
		ct.MaxTextSize = 18
		ct.Parent = charges
		charges.Parent = content
	end
	if not container:FindFirstChild("Overlay") then
		local overlay = Instance.new("Frame")
		overlay.Name = "Overlay"
		overlay.Size = UDim2.fromScale(1,1)
		overlay.BackgroundColor3 = Color3.new(0,0,0)
		overlay.BackgroundTransparency = OVERLAY_TRANSPARENCY
		overlay.BorderSizePixel = 0
		overlay.ZIndex = 2
		overlay.Parent = container
	end
	if not container:FindFirstChild("GCDOverlay") then
		local gcd = Instance.new("Frame")
		gcd.Name = "GCDOverlay"
		gcd.Size = UDim2.fromScale(1,1)
		gcd.BackgroundColor3 = Color3.new(0,0,0)
		gcd.BackgroundTransparency = GCD_OVERLAY_TRANSPARENCY
		gcd.BorderSizePixel = 0
		gcd.Visible = false
		gcd.ZIndex = 3
		gcd.Parent = container
	end
end

local function createSlot(slotIndex: number, skill: string): TextButton
	if not cachedTemplate then
		cachedTemplate = findTemplate()
	end
	local base: TextButton
	if cachedTemplate then
		base = cachedTemplate:Clone()
	else
		warn("SkillSlotUI: SkillSlotContainer template not found; using fallback")
		base = Instance.new("TextButton")
		base.Size = UDim2.fromOffset(64,64)
	end
	base.Text = ""
	base.Name = "SkillSlotContainer" .. slotIndex
	base.AutoButtonColor = false
	ensureSubLabels(base)
	local content = base:FindFirstChild("Content")
	local icon = content and content:FindFirstChild("Icon")
	if icon and icon:IsA("ImageLabel") then
		icon.Image = getIcon(skill)
		icon.ImageColor3 = READY_COLOR
	end
	local overlay = base:FindFirstChild("Overlay")
	if overlay and overlay:IsA("Frame") then
		overlay.BackgroundTransparency = OVERLAY_TRANSPARENCY
	end
	return base
end

local function enumerateSlots(): { { index: number, skill: string } }
	local filled = SkillSlots.getFilledSlots()
	if manualOrder then
		-- reorder to match manualOrder sequence (only include those that exist)
		local orderMap: { [number]: boolean } = {}
		for _, idx in ipairs(manualOrder) do
			orderMap[idx] = true
		end
		local result: { { index: number, skill: string } } = {}
		for _, idx in ipairs(manualOrder) do
			for _, slot in ipairs(filled) do
				if slot.index == idx then
					table.insert(result, slot)
				end
			end
		end
		-- append any remaining not specified
		for _, slot in ipairs(filled) do
			if not orderMap[slot.index] then
				table.insert(result, slot)
			end
		end
		return result
	end
	return filled
end

function SkillSlotUI._rebuild()
	if not rootFrame then return end
	destroyChildren(rootFrame)
	containerMap = {}
	slotSkillMap = {}
	-- disconnect previous per-slot connections
	for idx, conn in pairs(slotConnections) do
		local ok, err = pcall(function()
			conn:Disconnect()
		end)
		if not ok then
			warn("SkillSlotUI: error disconnecting slot connection", idx, err)
		end
		slotConnections[idx] = nil
	end

	local existingLayout = rootFrame:FindFirstChildOfClass("UIListLayout")
	if not existingLayout then
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(0, 6)
		layout.Parent = rootFrame
	end

	for order, info in ipairs(enumerateSlots()) do
		local slotFrame = createSlot(info.index, info.skill)
		slotFrame.LayoutOrder = order
		slotFrame.Parent = rootFrame
		containerMap[info.index] = slotFrame
		slotSkillMap[info.index] = info.skill
		-- capture new connection so we can clean it later
		-- Rebind activation explicitly to track handle
		if slotConnections[info.index] then
			-- should not happen after cleanup, but guard
			slotConnections[info.index]:Disconnect()
		end
		local conn = slotFrame.Activated:Connect(function()
			SkillSlots.activate(info.index)
		end)
		slotConnections[info.index] = conn
	end
end

local function formatTime(rem: number): string
	if rem <= 0 then return "" end
	if rem >= 60 then
		local m = math.floor(rem / 60)
		local s = math.floor(rem % 60)
		return string.format("%d:%02d", m, s)
	elseif rem >= 10 then
		return tostring(math.floor(rem + 0.5))
	else
		return string.format("%.1f", rem)
	end
end

local function updateOne(slotIndex: number, frame: TextButton, skill: string, gcdRemaining: number, gcdFraction: number)
	slotIndex = slotIndex -- suppress unused warning; retained for future per-slot custom logic
	local content = frame:FindFirstChild("Content")
	local icon = content and content:FindFirstChild("Icon") :: ImageLabel?
	local timer = content and content:FindFirstChild("Timer") :: TextLabel?
	local chargesLbl = content and content:FindFirstChild("Charges") :: TextLabel?
	local overlay = frame:FindFirstChild("Overlay") :: Frame?
	local gcdOverlay = frame:FindFirstChild("GCDOverlay") :: Frame?
	if not icon or not overlay or not gcdOverlay then return end

	local remaining = CooldownClient.getRemaining(skill)
	local rec = CooldownClient.get(skill)
	-- local frac optional; remaining fraction derived inline for overlay sizing

	local currentCharges, maxCharges = CooldownClient.getCharges(skill)
	local hasCharges = (maxCharges == 0) or (currentCharges > 0)

	-- Determine if we visually show the per-skill cooldown (avoid ultra-short spam from combo micro cds)
	local showSkillOverlay = (remaining > 0 and rec and rec.duration >= MIN_VISUAL_DURATION)
	if showSkillOverlay and rec then
		overlay.Visible = true
		overlay.Size = UDim2.fromScale(1, remaining / rec.duration)
		overlay.Position = UDim2.fromScale(0, 1 - (remaining / rec.duration))
	else
		overlay.Visible = false
	end

	-- GCD overlay (faint) independent of per-skill, show only if gcd active and skill itself not on a longer cd
	if gcdRemaining > 0 and (remaining <= gcdRemaining) then
		gcdOverlay.Visible = true
		gcdOverlay.Size = UDim2.fromScale(1, gcdFraction)
		gcdOverlay.Position = UDim2.fromScale(0, 1 - gcdFraction)
	else
		gcdOverlay.Visible = false
	end

	-- Timer text only when remaining <= 10 or no charges case waiting
	if timer then
		if remaining > 0 and remaining <= 10 then
			timer.Text = formatTime(remaining)
			timer.Visible = true
		else
			timer.Visible = false
		end
	end

	-- Charges
	if chargesLbl then
		if maxCharges > 1 then
			chargesLbl.Text = "x" .. tostring(currentCharges)
			chargesLbl.Visible = true
		else
			chargesLbl.Visible = false
		end
	end

	-- Desaturate if unusable (but ignore ultra-short micro cds below threshold; they rely on GCD overlay only)
	local shouldDesat = ((remaining > 0 and rec and rec.duration >= MIN_VISUAL_DURATION) or (not hasCharges) or gcdOverlay.Visible)
	if shouldDesat then
		icon.ImageColor3 = DESAT_COLOR
	else
		icon.ImageColor3 = READY_COLOR
	end
end

local function getGCD(): (number, number)
	-- Represent GCD via reserved key _GCD in CooldownClient (server uses that).
	local gcdRec = CooldownClient.get("_GCD")
	if not gcdRec then return 0, 0 end
	local nowT = os.clock()
	local rem = math.max(0, gcdRec.endAt - nowT)
	if rem <= 0 then return 0, 0 end
	local frac = if gcdRec.duration > 0 then math.clamp(rem / gcdRec.duration, 0, 1) else 0
	return rem, frac
end

local function updateLoop()
	if updating then return end
	updating = true
	local lastTick = 0
	while rootFrame do
		local gcdRem, gcdFrac = getGCD()
		local soonest = NORMAL_INTERVAL
		for slotIndex, frame in pairs(containerMap) do
			local skill = slotSkillMap[slotIndex]
			local remaining = CooldownClient.getRemaining(skill)
			if remaining > 0 and remaining < FAST_THRESHOLD then
				soonest = math.min(soonest, 0.016)
			end
			updateOne(slotIndex, frame, skill, gcdRem, gcdFrac)
		end
		RunService.Heartbeat:Wait()
		lastTick += 1
		if soonest > 0.02 then
			-- simple throttle by skipping cycles (approx)
			local skip = math.floor((soonest / 0.016) - 1)
			for _ = 1, skip do
				if not rootFrame then break end
				RunService.Heartbeat:Wait()
			end
		end
	end
	updating = false
end

function SkillSlotUI._connectSignals()
	local off1 = SkillSlots.onSlotsChanged(function()
		SkillSlotUI._rebuild()
	end)
	local off2 = SkillSlots.onProfileChanged(function()
		SkillSlotUI._rebuild()
	end)
	local off3 = CooldownClient.onChanged(function(_evt, _key)
		-- passive; updateLoop handles drawing
	end)
	connCleanup = { off1, off2, off3 }
end

function SkillSlotUI.mount(parent: Frame)
	if rootFrame then return function() end end
	rootFrame = parent
	SkillSlotUI._rebuild()
	SkillSlotUI._connectSignals()
	task.spawn(updateLoop)
	return function()
		clearConnections()
		-- disconnect slot activation connections
		for idx, conn in pairs(slotConnections) do
			local ok, err = pcall(function()
				conn:Disconnect()
			end)
			if not ok then
				warn("SkillSlotUI: error disconnecting on unmount", idx, err)
			end
			slotConnections[idx] = nil
		end
		if rootFrame then
			rootFrame:Destroy()
			rootFrame = nil
		end
	end
end

return SkillSlotUI
