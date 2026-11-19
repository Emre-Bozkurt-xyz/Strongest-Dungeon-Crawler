--!strict
-- Stages: small test maps built by hand in Studio and loaded one at a time during a dev session.
--
-- Stages live only in the place file, as Models under ServerStorage.Scenarios. Loading clones one
-- into Workspace.Stage; switching or unloading destroys that folder, so every load starts clean and
-- anything a scenario parented into `stage.folder` goes with it. The baseplate world is never touched.
--
-- Stages are placed far from the baseplate world (STAGE_ORIGIN) so the two never overlap and
-- streaming treats them as separate areas; a stage Model with the attribute `KeepPosition = true`
-- stays where it was authored. Because StreamingEnabled is on, `place` asks the engine to stream the
-- destination before moving anyone there.
--
-- This module only describes a stage (markers, spawn requests, attributes). Spawning what a stage
-- asks for, and characters, are the callers' job.

local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Markers = require(script.Markers)

export type SpawnRequest = {
	kind: string,
	cframe: CFrame,
	options: { [string]: any },
	marker: Instance,
}

type StageData = {
	name: string,
	model: Model,
	folder: Folder,
	_entries: { Markers.Entry },
	_pivot: Vector3,
}

local Stage = {}
Stage.__index = Stage

export type Stage = typeof(setmetatable({} :: StageData, Stage))

local Stages = {}

Stages.CONTAINER_NAME = "Scenarios"
Stages.MARKER_TAG = Markers.TAG
-- Stages sit 10000 studs along +Z, at ground level, orientation untouched (the pivot lands exactly here).
Stages.STAGE_ORIGIN = CFrame.new(0, 0, 10000)

local STAGE_FOLDER_NAME = "Stage"
local KEEP_POSITION_ATTRIBUTE = "KeepPosition"
local SPAWN_ATTRIBUTE = "Spawn"
local PLAYER_START_NAME = "PlayerStart"
-- Character root height above the floor when standing; keeps a placed character out of the ground.
local STAND_HEIGHT = 3.5
local FALLBACK_START_HEIGHT = 5
local STREAM_TIMEOUT = 5

local currentStage: Stage? = nil
local markersVisible = false
local listeners: { [number]: (Stage?) -> () } = {}
local nextListenerId = 0

-- "AreaLevel" -> "areaLevel", "XPValue" -> "xpValue": an attribute name reads as an option name.
local function lowerCamel(key: string): string
	local run = key:match("^%u+") or ""
	local length = #run
	if length == 0 then
		return key
	end
	if length == #key then
		return key:lower()
	end
	if length == 1 then
		return key:sub(1, 1):lower() .. key:sub(2)
	end
	return run:sub(1, length - 1):lower() .. key:sub(length)
end

local function alive(entry: Markers.Entry): boolean
	return entry.instance.Parent ~= nil
end

function Stage.marker(self: Stage, name: string): CFrame?
	for _, entry in ipairs(self._entries) do
		if entry.name == name and alive(entry) then
			return Markers.cframeOf(entry.instance)
		end
	end
	return nil
end

function Stage.markers(self: Stage, name: string): { CFrame }
	local result: { CFrame } = {}
	for _, entry in ipairs(self._entries) do
		if entry.name == name and alive(entry) then
			table.insert(result, Markers.cframeOf(entry.instance))
		end
	end
	return result
end

function Stage.markerNames(self: Stage): { string }
	local names: { string } = {}
	local last: string? = nil
	-- Entries are already sorted by name, so equal names are adjacent.
	for _, entry in ipairs(self._entries) do
		if entry.name ~= last and alive(entry) then
			table.insert(names, entry.name)
			last = entry.name
		end
	end
	return names
end

-- With no name: every marker, grouped by name in the same order as markerNames.
function Stage.markerInstances(self: Stage, name: string?): { Instance }
	local result: { Instance } = {}
	for _, entry in ipairs(self._entries) do
		if (name == nil or entry.name == name) and alive(entry) then
			table.insert(result, entry.instance)
		end
	end
	return result
end

-- Where a character stands on a marker. Only the marker's heading is kept: a marker tilted on a
-- slope should not tilt the character. Measured from the top face so a thick marker slab still puts
-- the character on top of it.
local function standOn(instance: Instance): CFrame
	local cframe = Markers.cframeOf(instance)
	local halfHeight = if instance:IsA("BasePart") then instance.Size.Y / 2 else 0
	local position = cframe.Position + Vector3.new(0, halfHeight + STAND_HEIGHT, 0)
	local heading = Vector3.new(cframe.LookVector.X, 0, cframe.LookVector.Z)
	if heading.Magnitude < 1e-3 then
		heading = Vector3.new(0, 0, -1)
	end
	return CFrame.lookAt(position, position + heading)
end

-- Where a character stands on the first marker with this name, or nil when there is none.
function Stage.standAt(self: Stage, name: string): CFrame?
	for _, entry in ipairs(self._entries) do
		if entry.name == name and alive(entry) then
			return standOn(entry.instance)
		end
	end
	return nil
end

function Stage.playerStart(self: Stage): CFrame
	local start = self:standAt(PLAYER_START_NAME)
	if start then
		return start
	end
	local boxCFrame, boxSize = self.model:GetBoundingBox()
	return CFrame.new(boxCFrame.Position + Vector3.new(0, boxSize.Y / 2 + FALLBACK_START_HEIGHT, 0))
end

-- A marker's `Spawn` attribute names what to put there; every other attribute becomes an option of
-- the request, so the scenario data lives on the marker in Studio rather than in code. `Order` is
-- excluded because it positions the marker in a list rather than describing what spawns.
function Stage.spawnRequests(self: Stage): { SpawnRequest }
	local requests: { SpawnRequest } = {}
	for _, entry in ipairs(self._entries) do
		local instance = entry.instance
		local kind = instance:GetAttribute(SPAWN_ATTRIBUTE)
		if alive(entry) and type(kind) == "string" and kind ~= "" then
			local options: { [string]: any } = {}
			for key, value in pairs(instance:GetAttributes()) do
				if key ~= SPAWN_ATTRIBUTE and key ~= "Order" then
					options[lowerCamel(key)] = value
				end
			end
			table.insert(requests, {
				kind = kind,
				cframe = Markers.cframeOf(instance),
				options = options,
				marker = instance,
			})
		end
	end
	return requests
end

function Stage.attributes(self: Stage): { [string]: any }
	return self.model:GetAttributes()
end

local function fire(stage: Stage?)
	for _, callback in pairs(listeners) do
		task.spawn(callback, stage)
	end
end

local function destroyCurrent(): boolean
	local stage = currentStage
	if not stage then
		return false
	end
	currentStage = nil
	stage.folder:Destroy()
	return true
end

function Stages.list(): { string }
	local names: { string } = {}
	local container = ServerStorage:FindFirstChild(Stages.CONTAINER_NAME)
	if container then
		for _, child in ipairs(container:GetChildren()) do
			if child:IsA("Model") then
				table.insert(names, child.Name)
			end
		end
	end
	table.sort(names)
	return names
end

-- The previous stage is only destroyed once the requested one is known to exist, so a typo does not
-- cost the stage you were in. Listeners hear one change per load, even when it replaces another stage.
function Stages.load(name: string): (Stage?, string?)
	local container = ServerStorage:FindFirstChild(Stages.CONTAINER_NAME)
	if not container then
		return nil, `ServerStorage.{Stages.CONTAINER_NAME} does not exist`
	end
	local source = container:FindFirstChild(name)
	if not source or not source:IsA("Model") then
		return nil, `No stage Model named "{name}" in ServerStorage.{Stages.CONTAINER_NAME}`
	end
	local clone = source:Clone() :: Model?
	if not clone then
		return nil, `Stage "{name}" could not be cloned (is Archivable off?)`
	end

	destroyCurrent()

	if source:GetAttribute(KEEP_POSITION_ATTRIBUTE) ~= true then
		clone:PivotTo(Stages.STAGE_ORIGIN)
	end

	local folder = Instance.new("Folder")
	folder.Name = STAGE_FOLDER_NAME
	clone.Parent = folder

	local instances = Markers.discover(clone)
	for _, instance in ipairs(instances) do
		Markers.prepare(instance, markersVisible)
	end
	local pivot = clone:GetPivot().Position

	local data: StageData = {
		name = name,
		model = clone,
		folder = folder,
		_entries = Markers.entries(instances, pivot),
		_pivot = pivot,
	}
	local stage = setmetatable(data, Stage)
	currentStage = stage
	folder.Parent = Workspace

	fire(stage)
	return stage, nil
end

function Stages.unload()
	if destroyCurrent() then
		fire(nil)
	end
end

function Stages.current(): Stage?
	return currentStage
end

function Stages.onChanged(callback: (Stage?) -> ()): () -> ()
	nextListenerId += 1
	local id = nextListenerId
	listeners[id] = callback
	return function()
		listeners[id] = nil
	end
end

-- Streaming is requested first because the server places the character instantly but the owning
-- client only has the area the engine has streamed in; without it they would fall through the void.
-- The character is re-read after the yield since it can die or respawn while streaming.
function Stages.place(player: Player, cframe: CFrame): boolean
	if not (player.Character and player.Character.PrimaryPart) then
		return false
	end

	if Workspace.StreamingEnabled then
		pcall(function()
			player:RequestStreamAroundAsync(cframe.Position, STREAM_TIMEOUT)
		end)
	end

	local character = player.Character
	local root = character and character.PrimaryPart
	if not (character and root) then
		return false
	end
	character:PivotTo(cframe)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	return true
end

local function worldEntries(): { Markers.Entry }
	local stage = currentStage
	local instances = Markers.discoverWorld(if stage then stage.folder else nil)
	for _, instance in ipairs(instances) do
		Markers.prepare(instance, markersVisible)
	end
	return Markers.entries(instances, Vector3.zero)
end

-- World markers are found when asked for, since the baseplate world is not loaded through here; this
-- hides and disarms them without needing a query first.
function Stages.prepareWorld()
	worldEntries()
end

function Stages.worldMarker(name: string): CFrame?
	for _, entry in ipairs(worldEntries()) do
		if entry.name == name then
			return Markers.cframeOf(entry.instance)
		end
	end
	return nil
end

function Stages.worldMarkers(name: string): { CFrame }
	local result: { CFrame } = {}
	for _, entry in ipairs(worldEntries()) do
		if entry.name == name then
			table.insert(result, Markers.cframeOf(entry.instance))
		end
	end
	return result
end

function Stages.worldStandAt(name: string): CFrame?
	for _, entry in ipairs(worldEntries()) do
		if entry.name == name then
			return standOn(entry.instance)
		end
	end
	return nil
end

-- Where a character stands on the named marker: the loaded stage's, else the world's.
function Stages.standAt(name: string): CFrame?
	local stage = currentStage
	return (stage and stage:standAt(name)) or Stages.worldStandAt(name)
end

-- Where players arrive in the baseplate world: a world `PlayerStart` marker, else the world's
-- SpawnLocation, else above the origin.
function Stages.worldStart(): CFrame
	local marker = Stages.worldStandAt(PLAYER_START_NAME)
	if marker then
		return marker
	end
	local stage = currentStage
	for _, descendant in ipairs(Workspace:GetDescendants()) do
		if descendant:IsA("SpawnLocation") and not (stage and descendant:IsDescendantOf(stage.folder)) then
			local top = descendant.Position + Vector3.new(0, descendant.Size.Y / 2 + STAND_HEIGHT, 0)
			return CFrame.new(top)
		end
	end
	return CFrame.new(0, FALLBACK_START_HEIGHT, 0)
end

-- Where players arrive now: the loaded stage's start, else the world's.
function Stages.start(): CFrame
	local stage = currentStage
	return if stage then stage:playerStart() else Stages.worldStart()
end

function Stages.worldMarkerNames(): { string }
	local names: { string } = {}
	local last: string? = nil
	for _, entry in ipairs(worldEntries()) do
		if entry.name ~= last then
			table.insert(names, entry.name)
			last = entry.name
		end
	end
	return names
end

function Stages.markersVisible(): boolean
	return markersVisible
end

-- Applies to the loaded stage and the world now, and to every later load.
function Stages.setMarkersVisible(visible: boolean)
	markersVisible = visible
	local stage = currentStage
	if stage then
		for _, entry in ipairs(stage._entries) do
			if alive(entry) then
				Markers.setVisible(entry.instance, visible)
			end
		end
	end
	worldEntries()
end

return Stages
