--!strict
-- Client Damage Number Controller
-- Shows floating damage numbers above enemies

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Networking = require(ReplicatedStorage.Shared.Networking)
local ClientRegistrar = require(script.Parent.Parent.ClientRegistrar)

local DamageNumberController = {}

type ActiveNumber = {
	gui: BillboardGui,
	targetId: string,
	damageType: string,
	amount: number,
	createdAt: number,
	anchorIndex: number?, -- Which anchor was used
}

-- State
local _activeNumbers: { [string]: ActiveNumber } = {}
local guiPool: { BillboardGui } = {} -- Inactive GUIs ready for reuse

-- Constants
local MAX_POOL_SIZE = 50 -- Maximum inactive GUIs to keep
local ANIMATION_DURATION = 0.9 -- Total animation time (snappier)
local POP_DURATION = 0.15 -- Initial pop-in time
local RISE_DISTANCE = 2.5 -- Studs to rise
local SPAWN_STAGGER = 0.03 -- Delay between multiple numbers (shorter for rapid feel)
local RANDOM_SPREAD = 1.5 -- Random horizontal spread radius
local HEIGHT_RANGE = 1 -- Random vertical spawn range
local HEIGHT_BASE = 1 -- Base height above entity
local DEBUG = false

-- Template
local template: BillboardGui? = nil
local templateSize: UDim2? = nil -- Store original size for reset

-- Damage type colors
local DAMAGE_COLORS = {
	Physical = Color3.fromRGB(255, 255, 255),
	Fire = Color3.fromRGB(255, 100, 50),
	Lightning = Color3.fromRGB(150, 200, 255),
	Ice = Color3.fromRGB(100, 200, 255),
	Poison = Color3.fromRGB(100, 255, 100),
	Dark = Color3.fromRGB(150, 100, 200),
	Light = Color3.fromRGB(255, 255, 150),
}

-- Utilities
local function _makeTypeKey(targetId: string, damageType: string): string
	return targetId .. "_" .. damageType
end

-- Get random spawn offset (Warframe-style)
local function getRandomSpawnOffset(): Vector3
	-- Random position in a sphere around the spawn point
	local angle = math.random() * math.pi * 2
	local radius = math.random() * RANDOM_SPREAD
	local height = HEIGHT_BASE + (math.random() - 0.5) * HEIGHT_RANGE

	local offsetX = math.cos(angle) * radius
	local offsetZ = math.sin(angle) * radius

	return Vector3.new(offsetX, height, offsetZ)
end

-- Get template GUI
local function getTemplate(): BillboardGui?
	if not template then
		local assets = ReplicatedStorage:FindFirstChild("Assets")
		local worldUI = assets and assets:FindFirstChild("WorldUI")
		template = worldUI and worldUI:FindFirstChild("DamageLabel") :: BillboardGui?

		if not template then
			warn("[DamageNumbers] Template 'DamageLabel' not found in ReplicatedStorage/Assets/WorldUI/")
		else
			-- Store original size for resetting scaled GUIs
			templateSize = template.Size
		end
	end
	return template
end

-- Get GUI from pool or create new
local function getFromPool(): BillboardGui?
	local tmpl = getTemplate()
	if not tmpl then
		return nil
	end

	-- Try to reuse from pool
	if #guiPool > 0 then
		local gui = table.remove(guiPool)
		if gui and gui.Parent == nil then
			return gui
		end
	end

	-- Create new from template
	local gui = tmpl:Clone()
	return gui
end

-- Return GUI to pool
local function returnToPool(gui: BillboardGui)
	if #guiPool >= MAX_POOL_SIZE then
		gui:Destroy()
		return
	end

	-- Reset state
	gui.Parent = nil
	(gui :: any).Adornee = nil
	gui.StudsOffset = Vector3.zero

	-- Reset size to original (in case it was scaled for crit)
	if templateSize then
		gui.Size = templateSize
	end

	local label = gui:FindFirstChild("AmountLabel") :: TextLabel?
	if label then
		label.TextTransparency = 0
		label.TextStrokeTransparency = 0
		label.Text = ""
	end

	table.insert(guiPool, gui)
end

-- Find character model from entityId
local function findCharacter(entityId: string): Model?
	local entity = ClientRegistrar.getEntity(entityId)
	if not entity then
		return nil
	end

	-- Entity might be the character model itself, or a child of it
	if entity:IsA("Model") and entity:FindFirstChild("HumanoidRootPart") then
		return entity
	end

	-- Check parent
	local parent = entity.Parent
	if parent and parent:IsA("Model") and parent:FindFirstChild("HumanoidRootPart") then
		return parent
	end

	return nil
end

-- Find all damage number spawn anchors in character
local function findDamageAnchors(character: Model): { Attachment }
	local anchors: { Attachment } = {}

	for _, desc in character:GetDescendants() do
		if desc:IsA("Attachment") and desc.Name:match("^DamageNumberSpawn") then
			table.insert(anchors, desc)
		end
	end

	return anchors
end

-- Get spawn position - simplified random approach
local function getSpawnPosition(character: Model): (Instance?, Vector3)
	local anchors = findDamageAnchors(character)

	-- If anchors exist, pick one randomly and add random offset
	if #anchors > 0 then
		local anchor = anchors[math.random(1, #anchors)]
		return anchor, getRandomSpawnOffset()
	end

	-- Fallback: use HumanoidRootPart with random offset
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if hrp then
		return hrp, getRandomSpawnOffset()
	end

	return nil, Vector3.zero
end

-- Animate damage number (pop in + rise + fade - Warframe style)
local function animateNumber(gui: BillboardGui, startOffset: Vector3)
	local label = gui:FindFirstChild("AmountLabel") :: TextLabel?
	if not label then
		returnToPool(gui)
		return
	end

	-- Store original size for pop animation
	local originalSize = gui.Size

	-- Start small for pop-in effect
	gui.Size = UDim2.new(originalSize.X.Scale * 0.5, 0, originalSize.Y.Scale * 0.5, 0)
	label.TextTransparency = 0.3
	label.TextStrokeTransparency = 0.3

	-- Pop-in: elastic scale to full size
	local popTween = TweenService:Create(
		gui,
		TweenInfo.new(POP_DURATION, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = originalSize }
	)

	-- Pop-in transparency
	local popFadeTween = TweenService:Create(
		label,
		TweenInfo.new(POP_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ TextTransparency = 0, TextStrokeTransparency = 0 }
	)

	-- Calculate end position (rise up)
	local endOffset = startOffset + Vector3.new(0, RISE_DISTANCE, 0)

	-- Rise and fade (starts after pop)
	local riseDuration = ANIMATION_DURATION - POP_DURATION
	local positionTween = TweenService:Create(
		gui,
		TweenInfo.new(riseDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ StudsOffset = endOffset }
	)

	local fadeTween = TweenService:Create(
		label,
		TweenInfo.new(riseDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ TextTransparency = 1, TextStrokeTransparency = 1 }
	)

	-- Play pop animation first
	popTween:Play()
	popFadeTween:Play()

	-- Then play rise and fade after pop completes
	task.delay(POP_DURATION, function()
		positionTween:Play()
		fadeTween:Play()
	end)

	-- Return to pool when complete
	fadeTween.Completed:Connect(function()
		returnToPool(gui)
	end)
end

-- Called when server HitEvent arrives
function DamageNumberController.onServerHit(event: { sourceId: string, targetId: string, result: any })
	if DEBUG then
		print(
			`[DamageNumbers] Server hit: sourceId={event.sourceId}, targetId={event.targetId}, total={event.result.totalDamage}, byType=`,
			event.result.byType
		)
	end

	-- Show damage number
	DamageNumberController.showNumber(event.targetId, event.result)
end

-- Show damage number(s) for a result (no pooling - Warframe style)
function DamageNumberController.showNumber(targetId: string, result: any)
	if DEBUG then
		print(`[DamageNumbers] Showing number for {targetId}: {result.totalDamage} damage`)
	end

	-- Handle special cases
	if result.dodged then
		-- TODO: Show "DODGED" text
		print(`[DamageNumbers] DODGED`)
		return
	end

	if result.blocked and result.totalDamage == 0 then
		-- TODO: Show "BLOCKED" text
		print(`[DamageNumbers] BLOCKED`)
		return
	end

	-- Show numbers for each damage type with slight stagger for visual cascade
	local spawnIndex = 0
	for damageType, amount in result.byType do
		if amount > 0 then
			spawnIndex += 1
			local delay = (spawnIndex - 1) * SPAWN_STAGGER

			task.delay(delay, function()
				DamageNumberController.spawnNumber(targetId, amount, damageType, result)
			end)
		end
	end
end

-- Spawn a damage number GUI (simplified - no index needed)
function DamageNumberController.spawnNumber(targetId: string, amount: number, damageType: string, metadata: any)
	-- Find target character
	local character = findCharacter(targetId)
	if not character then
		if DEBUG then
			warn(`[DamageNumbers] Could not find character for entity {targetId}`)
		end
		return
	end

	-- Get GUI from pool
	local gui = getFromPool()
	if not gui then
		return
	end

	-- Get random spawn position (each number independent)
	local adornee, studsOffset = getSpawnPosition(character)
	if not adornee then
		returnToPool(gui)
		return
	end

	-- Set adornee and position
	gui.Adornee = adornee
	gui.StudsOffset = studsOffset

	-- Configure label
	local label = gui:FindFirstChild("AmountLabel") :: TextLabel?
	if label then
		-- Build text with crit markers (Warframe style)
		local displayText = tostring(math.floor(amount))
		local critLevel = 0

		if metadata.crit then
			-- Determine crit level (future: could be passed from server based on crit chance thresholds)
			-- For now, assume single crit (level 1)
			critLevel = 1

			-- Add exclamation marks: "!" for 1x, "!!" for 2x, "!!!" for 3x (max)
			local markers = string.rep("!", math.min(critLevel, 3))
			displayText = displayText .. markers
		end

		label.Text = displayText

		-- Always use damage type color (crits don't get special color)
		label.TextColor3 = DAMAGE_COLORS[damageType] or DAMAGE_COLORS.Physical

		-- Reset transparency
		label.TextTransparency = 0
		label.TextStrokeTransparency = 0
	end

	-- Scale BillboardGui for crit emphasis (subtle size increase)
	if metadata.crit then
		local baseSize = gui.Size
		local critScale = 1.25 -- 25% larger for crits
		gui.Size =
			UDim2.new(baseSize.X.Scale * critScale, baseSize.X.Offset, baseSize.Y.Scale * critScale, baseSize.Y.Offset)
	end

	-- Parent to workspace to make visible
	gui.Parent = workspace

	-- Animate with slight random variation for organic feel
	local riseVariation = (math.random() - 0.5) * 0.5 -- ±0.25 studs
	animateNumber(gui, gui.StudsOffset + Vector3.new(0, riseVariation, 0))

	if DEBUG then
		print(`[DamageNumbers] Spawned: {amount} {damageType} on {targetId}, crit={metadata.crit}`)
	end
end

-- Initialize
function DamageNumberController.init()
	local dispatcher = Networking.client()
	dispatcher:on("HitEvent", function(event)
		DamageNumberController.onServerHit(event)
	end)

	if DEBUG then
		print("[DamageNumbers] Initialized")
	end
end

return DamageNumberController
