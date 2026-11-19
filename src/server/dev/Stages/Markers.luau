--!strict
-- Markers: how a stage (or the baseplate world) names reference positions.
--
-- A marker is a BasePart or Attachment that is either tagged `ScenarioMarker` or sits anywhere inside
-- a Folder named `Markers`; designers pick whichever suits the map. Its Name is the marker name and
-- names may repeat. Marker parts are made invisible and inert so a stage plays like the map it models;
-- the authored look is remembered so a debug toggle can bring them back.
--
-- Repeated names are ordered by an `Order` attribute when present, otherwise by distance from a
-- reference point (the stage pivot), so "the third EnemySpot" means the same thing on every load.

local CollectionService = game:GetService("CollectionService")

local Markers = {}

Markers.TAG = "ScenarioMarker"
Markers.FOLDER_NAME = "Markers"

export type Entry = {
	instance: Instance,
	name: string,
	order: number?,
	distance: number,
	position: Vector3,
}

type Look = { transparency: number, material: Enum.Material }

local LABEL_NAME = "ScenarioMarkerLabel"
-- Shown when the authored marker was already fully transparent.
local FALLBACK_VISIBLE_TRANSPARENCY = 0.5

-- Weak so a destroyed stage takes its remembered looks with it.
local looks: { [BasePart]: Look } = setmetatable({}, { __mode = "k" }) :: any

local function isCandidate(instance: Instance): boolean
	return instance:IsA("BasePart") or instance:IsA("Attachment")
end

local function insideMarkersFolder(instance: Instance, root: Instance): boolean
	local node = instance.Parent
	while node and node ~= root do
		if node:IsA("Folder") and node.Name == Markers.FOLDER_NAME then
			return true
		end
		node = node.Parent
	end
	return false
end

function Markers.cframeOf(instance: Instance): CFrame
	if instance:IsA("Attachment") then
		return instance.WorldCFrame
	end
	return (instance :: BasePart).CFrame
end

-- Every marker below `root`, by tag or by Markers folder.
function Markers.discover(root: Instance): { Instance }
	local found: { Instance } = {}
	for _, descendant in ipairs(root:GetDescendants()) do
		if
			isCandidate(descendant)
			and (CollectionService:HasTag(descendant, Markers.TAG) or insideMarkersFolder(descendant, root))
		then
			table.insert(found, descendant)
		end
	end
	return found
end

-- Tagged markers placed straight in the world, outside any stage. Only the tag counts here: the world
-- is not a single authored model, so there is no root for a Markers folder to belong to.
function Markers.discoverWorld(excluding: Instance?): { Instance }
	local found: { Instance } = {}
	for _, tagged in ipairs(CollectionService:GetTagged(Markers.TAG)) do
		if
			isCandidate(tagged)
			and tagged:IsDescendantOf(workspace)
			and not (excluding and tagged:IsDescendantOf(excluding))
		then
			table.insert(found, tagged)
		end
	end
	return found
end

local function setLabel(instance: Instance, visible: boolean)
	local existing = instance:FindFirstChild(LABEL_NAME)
	if not visible then
		if existing then
			existing:Destroy()
		end
		return
	end
	if existing then
		return
	end

	local order = instance:GetAttribute("Order")
	local gui = Instance.new("BillboardGui")
	gui.Name = LABEL_NAME
	gui.AlwaysOnTop = true
	gui.Size = UDim2.fromOffset(180, 26)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 1.5, 0)
	gui.MaxDistance = 250
	gui.Adornee = instance :: any

	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.Font = Enum.Font.GothamMedium
	text.TextSize = 18
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextStrokeTransparency = 0.3
	text.Text = if type(order) == "number" then `{instance.Name} #{order}` else instance.Name
	text.Parent = gui

	gui.Parent = instance
end

function Markers.setVisible(instance: Instance, visible: boolean)
	if instance:IsA("BasePart") then
		local look = looks[instance]
		if not look then
			return
		end
		if visible then
			instance.Transparency = if look.transparency < 1 then look.transparency else FALLBACK_VISIBLE_TRANSPARENCY
			instance.Material = Enum.Material.Neon
		else
			instance.Transparency = 1
			instance.Material = look.material
		end
	end
	setLabel(instance, visible)
end

-- Idempotent: the authored look is recorded once, before the part is first made inert.
function Markers.prepare(instance: Instance, visible: boolean)
	if instance:IsA("BasePart") and not looks[instance] then
		looks[instance] = { transparency = instance.Transparency, material = instance.Material }
		instance.Anchored = true
		instance.CanCollide = false
		instance.CanTouch = false
		instance.CanQuery = false
		instance.CastShadow = false
		instance.Transparency = 1
	end
	Markers.setVisible(instance, visible)
end

local function before(a: Entry, b: Entry): boolean
	if a.name ~= b.name then
		return a.name < b.name
	end

	local ao, bo = a.order, b.order
	if ao ~= nil and bo ~= nil then
		if ao ~= bo then
			return ao < bo
		end
	elseif ao ~= nil or bo ~= nil then
		return ao ~= nil
	elseif a.distance ~= b.distance then
		return a.distance < b.distance
	end

	local ap, bp = a.position, b.position
	if ap.X ~= bp.X then
		return ap.X < bp.X
	end
	if ap.Y ~= bp.Y then
		return ap.Y < bp.Y
	end
	return ap.Z < bp.Z
end

-- Sorted by name, then by the repeat-order rule above, so one list answers every per-name query.
function Markers.entries(instances: { Instance }, reference: Vector3): { Entry }
	local entries: { Entry } = {}
	for _, instance in ipairs(instances) do
		local position = Markers.cframeOf(instance).Position
		local order = instance:GetAttribute("Order")
		table.insert(entries, {
			instance = instance,
			name = instance.Name,
			order = if type(order) == "number" then order else nil,
			distance = (position - reference).Magnitude,
			position = position,
		})
	end
	table.sort(entries, before)
	return entries
end

return Markers
