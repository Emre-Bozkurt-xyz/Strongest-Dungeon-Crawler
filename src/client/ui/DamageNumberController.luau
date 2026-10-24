--!strict
-- Floating damage numbers over whatever was hit, from the server's HitEvent.
--
-- Warframe-style: one number per damage type, coloured by type, staggered slightly, spawned at random
-- around the target's DamageNumberSpawn attachments (or its root), with "!" markers and a larger
-- size on a crit. Blocked and dodged hits show as words.
--
-- Motion follows the rest of the UI: fixed times eased to a hard stop, no overshoot. A number snaps in,
-- rises, holds, and cuts out quickly. All live numbers are driven from one render loop rather than a
-- set of tweens each.
--
-- Screen UI projected from the hit point each frame, like the loot plates and enemy bars, rather than
-- a BillboardGui: one size at any distance, always over effects, and built here rather than cloned
-- from a Studio template, so it is versioned with the code like the rest of the UI.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Networking = require(ReplicatedStorage.Shared.Networking)
local Ease = require(ReplicatedStorage.Shared.ui.Ease)
local Themes = require(ReplicatedStorage.Shared.ui.themes)
local Registrar = require(script.Parent.Parent.Services.Registrar)

local DamageNumberController = {}

type LiveNumber = {
	label: TextLabel,
	scale: UIScale,
	stroke: UIStroke,
	-- What the number floats over, and where it started relative to that.
	anchor: Instance,
	from: Vector3,
	started: number,
	-- Final pop size: larger for a crit.
	size: number,
}

local live: { LiveNumber } = {}
local pool: { TextLabel } = {}
local loop: RBXScriptConnection? = nil
local layer: ScreenGui? = nil

local MAX_POOL_SIZE = 50
-- Seconds.
local LIFETIME = 0.9
local POP = 0.08
-- The number holds fully visible until this fraction of its life, then cuts out.
local FADE_FROM = 0.6
-- Studs.
local RISE_DISTANCE = 2.2
local RANDOM_SPREAD = 1.5
local HEIGHT_RANGE = 1
local HEIGHT_BASE = 1
-- Seconds between the numbers of one hit.
local SPAWN_STAGGER = 0.03
local CRIT_SCALE = 1.3
-- Pixels.
local TEXT_SIZE = 26
local DEBUG = false

local DAMAGE_COLORS = {
	Physical = Color3.fromRGB(255, 255, 255),
	Fire = Color3.fromRGB(255, 100, 50),
	Lightning = Color3.fromRGB(150, 200, 255),
	Ice = Color3.fromRGB(100, 200, 255),
	Poison = Color3.fromRGB(100, 255, 100),
	Dark = Color3.fromRGB(150, 100, 200),
	Light = Color3.fromRGB(255, 255, 150),
}

local function getRandomSpawnOffset(): Vector3
	local angle = math.random() * math.pi * 2
	local radius = math.random() * RANDOM_SPREAD
	local height = HEIGHT_BASE + (math.random() - 0.5) * HEIGHT_RANGE
	return Vector3.new(math.cos(angle) * radius, height, math.sin(angle) * radius)
end

local function getLayer(): ScreenGui
	if layer and layer.Parent then
		return layer
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "DamageNumbers"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	layer = gui
	return gui
end

local function buildLabel(): TextLabel
	local theme = Themes.getDefault()

	local label = Instance.new("TextLabel")
	label.Name = "DamageNumber"
	label.Size = UDim2.fromOffset(160, 48)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.BackgroundTransparency = 1
	label.FontFace = theme.face.display
	label.TextSize = TEXT_SIZE
	label.TextColor3 = DAMAGE_COLORS.Physical

	local scaler = Instance.new("UIScale")
	scaler.Parent = label

	local stroke = Instance.new("UIStroke")
	stroke.Color = theme.color.surface
	stroke.Thickness = 2
	stroke.Parent = label

	return label
end

local function takeLabel(): TextLabel
	local label = table.remove(pool)
	return label or buildLabel()
end

local function release(label: TextLabel)
	label.Parent = nil
	if #pool < MAX_POOL_SIZE then
		table.insert(pool, label)
	else
		label:Destroy()
	end
end

local function worldPosition(anchor: Instance): Vector3?
	if anchor:IsA("Attachment") then
		return anchor.WorldPosition
	elseif anchor:IsA("BasePart") then
		return anchor.Position
	end
	return nil
end

-- One frame for every live number; disconnects itself once there are none.
local function step()
	local now = os.clock()
	local camera = workspace.CurrentCamera
	local index = 1
	while index <= #live do
		local number = live[index]
		local t = Ease.clamp01((now - number.started) / LIFETIME)
		local base = worldPosition(number.anchor)
		if t >= 1 or not base or not camera then
			release(number.label)
			table.remove(live, index)
			continue
		end
		local pop = Ease.quartOut(Ease.clamp01((now - number.started) / POP))
		number.scale.Scale = number.size * (0.55 + 0.45 * pop)
		local world = (base :: Vector3) + number.from + Vector3.new(0, RISE_DISTANCE * Ease.quartOut(t), 0)
		local point = camera:WorldToViewportPoint(world)
		number.label.Visible = point.Z > 0
		number.label.Position = UDim2.fromOffset(math.round(point.X), math.round(point.Y))
		local fade = Ease.quartIn(Ease.clamp01((t - FADE_FROM) / (1 - FADE_FROM)))
		number.label.TextTransparency = fade
		number.stroke.Transparency = fade
		index += 1
	end
	if #live == 0 and loop then
		loop:Disconnect()
		loop = nil
	end
end

local function findCharacter(entityId: string): Model?
	local entity = Registrar.getEntity(entityId)
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

-- A random DamageNumberSpawn attachment if the character has any, else its root.
local function getSpawnAnchor(character: Model): Instance?
	local anchors: { Attachment } = {}
	for _, desc in character:GetDescendants() do
		if desc:IsA("Attachment") and desc.Name:match("^DamageNumberSpawn") then
			table.insert(anchors, desc)
		end
	end
	if #anchors > 0 then
		return anchors[math.random(1, #anchors)]
	end
	return character:FindFirstChild("HumanoidRootPart")
end

local function spawnText(targetId: string, text: string, color: Color3, crit: boolean)
	local character = findCharacter(targetId)
	local anchor = character and getSpawnAnchor(character)
	if not anchor then
		if DEBUG then
			warn(`[DamageNumbers] Could not find character for entity {targetId}`)
		end
		return
	end

	local label = takeLabel()
	label.Text = text
	label.TextColor3 = color
	label.TextTransparency = 0
	label.Visible = false
	label.Parent = getLayer()

	table.insert(live, {
		label = label,
		scale = label:FindFirstChildOfClass("UIScale") :: UIScale,
		stroke = label:FindFirstChildOfClass("UIStroke") :: UIStroke,
		anchor = anchor :: Instance,
		from = getRandomSpawnOffset() + Vector3.new(0, (math.random() - 0.5) * 0.5, 0),
		started = os.clock(),
		size = if crit then CRIT_SCALE else 1,
	})
	if not loop then
		loop = RunService.RenderStepped:Connect(step)
	end
end

function DamageNumberController.spawnNumber(targetId: string, amount: number, damageType: string, metadata: any)
	local text = tostring(math.floor(amount))
	-- "!" per crit level, up to three; the server reports a single level for now.
	if metadata.crit then
		text ..= "!"
	end
	spawnText(targetId, text, DAMAGE_COLORS[damageType] or DAMAGE_COLORS.Physical, metadata.crit == true)
end

-- Numbers for each damage type in a hit, staggered slightly so they read as a cascade.
function DamageNumberController.showNumber(targetId: string, result: any)
	local muted = Themes.getDefault().color.textMuted
	if result.dodged then
		spawnText(targetId, "DODGED", muted, false)
		return
	end
	if result.blocked and result.totalDamage == 0 then
		spawnText(targetId, "BLOCKED", muted, false)
		return
	end

	local spawnIndex = 0
	for damageType, amount in result.byType do
		if amount > 0 then
			spawnIndex += 1
			task.delay((spawnIndex - 1) * SPAWN_STAGGER, function()
				DamageNumberController.spawnNumber(targetId, amount, damageType, result)
			end)
		end
	end
end

function DamageNumberController.onServerHit(event: { sourceId: string, targetId: string, result: any })
	if DEBUG then
		print(`[DamageNumbers] Server hit: target={event.targetId}, total={event.result.totalDamage}`)
	end
	DamageNumberController.showNumber(event.targetId, event.result)
end

function DamageNumberController.init()
	local dispatcher = Networking.client()
	dispatcher:on("HitEvent", function(event)
		DamageNumberController.onServerHit(event)
	end)
end

return DamageNumberController
