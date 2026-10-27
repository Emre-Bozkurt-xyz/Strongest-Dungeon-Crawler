--!strict
-- A mastery track's tree as one player sees it: which nodes exist, how they connect, where they sit,
-- and what state each is in. Pure: built from the tree data (MasteryTrees), the player's branch XP
-- and their form selection, so it can be rebuilt on every change and tested without a game running.
--
-- Also the one unlock rule (`isUnlocked`) the server checks selections against, so the canvas and
-- the server can never disagree about what is open.
--
-- Fog: a player sees what they have unlocked, the next node along each line in full, and the one
-- after only as an outline. Anything further is hidden, so a tree is discovered by progressing.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BasicAttackProfileRegistry = require(ReplicatedStorage.Shared.skills.BasicAttackProfileRegistry)
local MasteryTracks = require(script.Parent.MasteryTracks)
local MasteryTrees = require(script.Parent.MasteryTrees)
local MasteryXP = require(script.Parent.MasteryXP)

type NodeDef = MasteryTrees.NodeDef
type TreeDef = MasteryTrees.TreeDef

export type Visibility = "shown" | "fogged"

export type Node = {
	id: string,
	displayName: string,
	kind: MasteryTrees.NodeKind,
	description: string,
	-- Grid position: column left to right, row 0 (branch a) / 1 (trunk) / 2 (branch b).
	column: number,
	row: number,
	unlocked: boolean,
	-- Form nodes: the profile that implements this node for the held weapon, if any. Without one the
	-- node cannot be selected right now (not built yet, or it does not fit what is held).
	shapeId: string?,
	-- Whether any profile implements this node at all, for telling "not built yet" from "does not fit
	-- what you hold".
	built: boolean,
	-- The form in use for the held weapon: the player's selection, or the default when none is made.
	selected: boolean,
	isDefault: boolean,
	-- What it takes, for a locked node.
	requirement: string?,
	attributes: { [string]: string }?,
	visibility: Visibility,
}

export type BranchProgress = {
	name: string,
	xp: number,
	cap: number,
	rank: number,
	mastered: boolean,
}

export type Tree = {
	track: MasteryTracks.Track,
	-- Visible nodes only, in a stable order.
	nodes: { Node },
	edges: { { from: string, to: string } },
	columns: number,
	rows: number,
	branches: { [string]: BranchProgress },
}

local MasteryTree = {}

-- Every profile a tree names must exist; a typo would leave a form that can never be chosen.
for _, track in ipairs(MasteryTracks.list()) do
	local tree = MasteryTrees.get(track.id)
	assert(tree, `MasteryTree: no tree for track '{track.id}'`)
	for _, node in ipairs(tree.nodes) do
		for _, shapeId in ipairs(node.shapes or {}) do
			assert(
				BasicAttackProfileRegistry.get(shapeId),
				`MasteryTree: node '{node.id}' names unknown basic attack profile '{shapeId}'`
			)
		end
	end
end

local function findNode(tree: TreeDef, branch: string, rank: number?): NodeDef?
	for _, node in ipairs(tree.nodes) do
		if node.branch == branch and (rank == nil or node.rank == rank) then
			return node
		end
	end
	return nil
end

-- The nodes a node grows from: the previous rank along its line, the root for a branch's first
-- rank, both branches' JOIN_RANK for the join, the join for an element's end node.
function MasteryTree.parentsOf(tree: TreeDef, node: NodeDef): { NodeDef }
	local out: { NodeDef } = {}
	local function add(parent: NodeDef?)
		if parent then
			table.insert(out, parent)
		end
	end
	local rank = node.rank or 0
	if node.branch == "trunk" then
		if rank > 0 then
			add(findNode(tree, "trunk", rank - 1))
		end
	elseif node.branch == "a" or node.branch == "b" then
		add(if rank == 1 then findNode(tree, "trunk", 0) else findNode(tree, node.branch, rank - 1))
	elseif node.branch == "join" then
		add(findNode(tree, "a", MasteryXP.JOIN_RANK))
		add(findNode(tree, "b", MasteryXP.JOIN_RANK))
	elseif node.branch == "end" then
		add(findNode(tree, "join", nil))
	end
	return out
end

-- Whether `node` is open given the track's branch XP. `attuned` only matters for end nodes.
function MasteryTree.isUnlocked(node: NodeDef, branches: { [string]: number }, attuned: boolean?): boolean
	local rank = node.rank or 0
	if node.branch == "trunk" then
		return MasteryXP.rankOf("trunk", branches) >= rank
	elseif node.branch == "a" or node.branch == "b" then
		return MasteryXP.rankOf(node.branch, branches) >= rank
	elseif node.branch == "join" then
		return MasteryXP.rankOf("a", branches) >= MasteryXP.JOIN_RANK
			and MasteryXP.rankOf("b", branches) >= MasteryXP.JOIN_RANK
	elseif node.branch == "end" then
		return attuned == true
			and MasteryXP.rankOf("a", branches) >= MasteryXP.JOIN_RANK
			and MasteryXP.rankOf("b", branches) >= MasteryXP.JOIN_RANK
	end
	return false
end

-- Whether a basic attack profile may be selected, given every track's branch XP. A profile that
-- implements no node is not part of progression and is never selectable (defaults resolve without
-- being selected).
function MasteryTree.isShapeUnlocked(shapeId: string, masteries: { [string]: { [string]: number } }): boolean
	local node, tree = MasteryTrees.nodeForShape(shapeId)
	if not node or not tree then
		return false
	end
	return MasteryTree.isUnlocked(node, masteries[tree.track] or {}, nil)
end

-- Which branches a use of `node` feeds, and how much of it each takes. A join form sits beyond both
-- branches and feeds them equally; an end node feeds the trunk.
function MasteryTree.creditFor(node: NodeDef): { [string]: number }
	if node.branch == "a" or node.branch == "b" then
		return { [node.branch] = 1 }
	elseif node.branch == "join" then
		return { a = 0.5, b = 0.5 }
	end
	return { trunk = 1 }
end

local function position(node: NodeDef): (number, number)
	local rank = node.rank or 0
	if node.branch == "trunk" then
		return rank, 1
	elseif node.branch == "a" then
		return rank, 0
	elseif node.branch == "b" then
		return rank, 2
	elseif node.branch == "join" then
		return MasteryXP.JOIN_RANK + 1, 1
	end
	return MasteryXP.JOIN_RANK + 2, 1
end

local function requirementOf(tree: TreeDef, track: MasteryTracks.Track, node: NodeDef): string
	local rank = node.rank or 0
	if node.branch == "trunk" then
		return `REQUIRES {MasteryXP.TRUNK_RANKS[rank]} TRUNK XP`
	elseif node.branch == "a" or node.branch == "b" then
		if rank == 1 then
			return `REQUIRES {MasteryXP.BRANCH_ENTRY} TRUNK XP`
		end
		local name = (tree.branches :: any)[node.branch] :: string
		return `REQUIRES {MasteryXP.BRANCH_RANKS[rank]} {string.upper(name)} XP`
	elseif node.branch == "join" then
		return `REQUIRES {string.upper(tree.branches.a)} & {string.upper(tree.branches.b)} RANK {MasteryXP.JOIN_RANK}`
	end
	return `REQUIRES {string.upper(track.displayName)} ATTUNED`
end

-- The profile a weapon context uses when nothing is selected.
local function defaultShapeFor(context: string): string
	if context == "unarmed" then
		return BasicAttackProfileRegistry.getUnarmedProfile().id
	end
	return BasicAttackProfileRegistry.resolveForWeapon(nil, context, nil).id
end

-- `branches`: this track's branch XP. `context`: the held weapon's class key. `selectedShape`: the
-- player's selection for that context, if any.
function MasteryTree.build(
	trackId: string,
	branches: { [string]: number },
	context: string,
	selectedShape: string?,
	attuned: boolean?
): Tree?
	local track = MasteryTracks.get(trackId)
	local tree = MasteryTrees.get(trackId)
	if not track or not tree then
		return nil
	end

	local unlocked: { [string]: boolean } = {}
	for _, node in ipairs(tree.nodes) do
		unlocked[node.id] = MasteryTree.isUnlocked(node, branches, attuned)
	end

	-- Distance from the nearest unlocked node behind it: 0 when unlocked, 1 for the next along a line,
	-- 2 for the one after. A locked root counts as 1 so a tree's start is always readable.
	local distances: { [string]: number } = {}
	local function distance(node: NodeDef): number
		local known = distances[node.id]
		if known then
			return known
		end
		local d
		if unlocked[node.id] then
			d = 0
		else
			local parents = MasteryTree.parentsOf(tree, node)
			if #parents == 0 then
				d = 1
			else
				d = math.huge
				for _, parent in ipairs(parents) do
					d = math.min(d, distance(parent) + 1)
				end
			end
		end
		distances[node.id] = d
		return d
	end

	local defaultShape = defaultShapeFor(context)
	local selectedValid = false
	if selectedShape then
		local selectedNode = MasteryTrees.nodeForShape(selectedShape)
		local profile = BasicAttackProfileRegistry.get(selectedShape)
		selectedValid = selectedNode ~= nil
			and profile ~= nil
			and BasicAttackProfileRegistry.fitsClass(profile, context)
			and unlocked[selectedNode.id] == true
	end
	local inUse = if selectedValid then selectedShape else defaultShape

	local nodes: { Node } = {}
	local edges: { { from: string, to: string } } = {}
	local visible: { [string]: boolean } = {}
	local maxColumn = 0
	for _, node in ipairs(tree.nodes) do
		local d = distance(node)
		if d <= 2 then
			visible[node.id] = true
			local column, row = position(node)
			maxColumn = math.max(maxColumn, column)
			local shapeId: string? = nil
			for _, candidate in ipairs(node.shapes or {}) do
				local profile = BasicAttackProfileRegistry.get(candidate)
				if profile and BasicAttackProfileRegistry.fitsClass(profile, context) then
					shapeId = candidate
					break
				end
			end
			table.insert(nodes, {
				id = node.id,
				displayName = node.displayName,
				kind = node.kind,
				description = node.description,
				column = column,
				row = row,
				unlocked = unlocked[node.id],
				shapeId = shapeId,
				built = node.shapes ~= nil and #node.shapes > 0,
				selected = shapeId ~= nil and shapeId == inUse,
				isDefault = shapeId ~= nil and shapeId == defaultShape,
				requirement = if unlocked[node.id] then nil else requirementOf(tree, track, node),
				attributes = node.attributes,
				visibility = if d >= 2 then "fogged" else "shown",
			})
		end
	end
	for _, node in ipairs(tree.nodes) do
		if visible[node.id] then
			for _, parent in ipairs(MasteryTree.parentsOf(tree, node)) do
				if visible[parent.id] then
					table.insert(edges, { from = parent.id, to = node.id })
				end
			end
		end
	end

	table.sort(nodes, function(a, b)
		if a.column ~= b.column then
			return a.column < b.column
		end
		return a.row < b.row
	end)

	local progress: { [string]: BranchProgress } = {}
	for _, branch in ipairs({ "trunk", "a", "b" }) do
		local xp = branches[branch] or 0
		progress[branch] = {
			name = if branch == "trunk" then "Trunk" else (tree.branches :: any)[branch],
			xp = xp,
			cap = MasteryXP.capOf(branch),
			rank = MasteryXP.rankOf(branch, branches),
			mastered = MasteryXP.isMastered(branch, branches),
		}
	end

	return {
		track = track,
		nodes = nodes,
		edges = edges,
		columns = maxColumn + 1,
		rows = 3,
		branches = progress,
	}
end

return MasteryTree
