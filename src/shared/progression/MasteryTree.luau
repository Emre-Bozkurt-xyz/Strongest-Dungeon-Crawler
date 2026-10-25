--!strict
-- A mastery track's tree as the player sees it: which nodes exist, how they connect, where they sit,
-- and what state each is in for one player. Pure: built from the shape registry and the player's
-- levels and selection, so it can be rebuilt on every change and tested without a game running.
--
-- Today a track's nodes are the basic attack shapes for its class, joined by each shape's `parent`.
--
-- Fog: a player sees the nodes they have unlocked, the next node along each branch in full, and
-- the one after that only as an outline. Anything further is hidden until they get closer, so the
-- tree is discovered by progressing rather than read in advance.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BasicAttackProfileRegistry = require(ReplicatedStorage.Shared.skills.BasicAttackProfileRegistry)
local BasicAttackProfileTypes = require(ReplicatedStorage.Shared.skills.BasicAttackProfileTypes)
local MasteryTracks = require(script.Parent.MasteryTracks)

type Shape = BasicAttackProfileTypes.BasicAttackProfile

export type Visibility = "shown" | "fogged"

export type Requirement = {
	track: string,
	level: number,
}

export type Node = {
	id: string,
	displayName: string,
	-- Lineage depth (column) and position among its column (row), in grid units.
	column: number,
	row: number,
	parent: string?,
	unlocked: boolean,
	-- In use for this track's class: the player's selection, or the default when none is made.
	selected: boolean,
	isDefault: boolean,
	-- The requirements this node has, for showing what it takes.
	requirements: { Requirement },
	visibility: Visibility,
}

export type Tree = {
	track: MasteryTracks.Track,
	-- Visible nodes only, in a stable order.
	nodes: { Node },
	edges: { { from: string, to: string } },
	columns: number,
	rows: number,
}

local MasteryTree = {}

local function isDefaultFor(shape: Shape, classKey: string): boolean
	if classKey == BasicAttackProfileTypes.UNARMED_CLASS_KEY then
		return shape.id == BasicAttackProfileRegistry.getUnarmedProfile().id
	end
	return table.find(shape.weaponClasses, classKey :: any) ~= nil
end

local function requirementsOf(shape: Shape): { Requirement }
	local out: { Requirement } = {}
	local mastery = shape.requires and shape.requires.mastery
	for track, level in pairs(mastery or {}) do
		table.insert(out, { track = track, level = level })
	end
	table.sort(out, function(a, b)
		return a.track < b.track
	end)
	return out
end

-- `levels`: track id -> level. `selectedShape`: the player's selection for the track's class, if any.
function MasteryTree.build(trackId: string, levels: { [string]: number }, selectedShape: string?): Tree?
	local track = MasteryTracks.get(trackId)
	if not track then
		return nil
	end

	local shapes = BasicAttackProfileRegistry.shapesFor(track.classKey)
	local inTree: { [string]: Shape } = {}
	for _, shape in ipairs(shapes) do
		inTree[shape.id] = shape
	end

	local childrenOf: { [string]: { string } } = {}
	local roots: { string } = {}
	for _, shape in ipairs(shapes) do
		local parent = shape.parent
		if parent and inTree[parent] then
			childrenOf[parent] = childrenOf[parent] or {}
			table.insert(childrenOf[parent], shape.id)
		else
			table.insert(roots, shape.id)
		end
	end

	local unlocked: { [string]: boolean } = {}
	for id, shape in pairs(inTree) do
		unlocked[id] = MasteryTracks.meets(levels, shape.requires)
	end

	-- Distance from the nearest unlocked ancestor: 0 when unlocked, 1 for the next node along a
	-- branch, 2 for the one after. A locked root has no unlocked ancestor and counts as 1, so the start
	-- of every branch is always readable.
	local function distance(id: string): number
		if unlocked[id] then
			return 0
		end
		local parent = inTree[id].parent
		if not parent or not inTree[parent] then
			return 1
		end
		return distance(parent) + 1
	end

	local selectedId = if selectedShape and inTree[selectedShape] and unlocked[selectedShape] then selectedShape else nil

	-- Tidy layout: each leaf takes the next row, and a parent sits centred on its children.
	local nodes: { Node } = {}
	local edges: { { from: string, to: string } } = {}
	local nextRow = 0
	local maxColumn = 0

	local function place(id: string, column: number): number?
		local d = distance(id)
		if d > 2 then
			return nil
		end
		local shape = inTree[id]
		local childRows: { number } = {}
		for _, childId in ipairs(childrenOf[id] or {}) do
			local childRow = place(childId, column + 1)
			if childRow then
				table.insert(childRows, childRow)
				table.insert(edges, { from = id, to = childId })
			end
		end
		local row: number
		if #childRows == 0 then
			row = nextRow
			nextRow += 1
		else
			row = (childRows[1] + childRows[#childRows]) / 2
		end
		maxColumn = math.max(maxColumn, column)
		local isDefault = isDefaultFor(shape, track.classKey)
		table.insert(nodes, {
			id = id,
			displayName = shape.displayName,
			column = column,
			row = row,
			parent = if shape.parent and inTree[shape.parent] then shape.parent else nil,
			unlocked = unlocked[id],
			selected = if selectedId then selectedId == id else isDefault,
			isDefault = isDefault,
			requirements = requirementsOf(shape),
			visibility = if d >= 2 then "fogged" else "shown",
		})
		return row
	end

	-- Defaults first so the tree reads from its starting point.
	table.sort(roots, function(a, b)
		local aDefault, bDefault = isDefaultFor(inTree[a], track.classKey), isDefaultFor(inTree[b], track.classKey)
		if aDefault ~= bDefault then
			return aDefault
		end
		return a < b
	end)
	for _, rootId in ipairs(roots) do
		place(rootId, 0)
	end

	table.sort(nodes, function(a, b)
		if a.column ~= b.column then
			return a.column < b.column
		end
		return a.row < b.row
	end)

	return {
		track = track,
		nodes = nodes,
		edges = edges,
		columns = maxColumn + 1,
		rows = math.max(nextRow, 1),
	}
end

return MasteryTree
