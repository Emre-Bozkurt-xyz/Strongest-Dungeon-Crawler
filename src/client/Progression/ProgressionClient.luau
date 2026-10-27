--!strict
-- ProgressionClient: the client's copy of the player's mastery progress and form selections
-- (server: MasteryService), and the System's announcements when they change.
--
-- The server sends the whole progression -- XP per track and branch, and the selected form per
-- weapon context -- whenever any of it changes; this keeps the latest and lets the mastery canvas
-- re-render from it. Selecting a form goes to the server, which answers with an update rather than
-- this guessing ahead: a selection is a menu action, not a combat one, so a round trip costs nothing
-- the player feels.
--
-- Announcements compare each update with the last: a level reached (the server marks those), and
-- any node that opened or branch that was Mastered since.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Networking = require(ReplicatedStorage.Shared.Networking)
local MasteryTracks = require(ReplicatedStorage.Shared.progression.MasteryTracks)
local MasteryTrees = require(ReplicatedStorage.Shared.progression.MasteryTrees)
local MasteryTree = require(ReplicatedStorage.Shared.progression.MasteryTree)
local MasteryXP = require(ReplicatedStorage.Shared.progression.MasteryXP)
local NotificationClient = require(script.Parent.Parent.ui.controllers.NotificationClient)
local UISound = require(script.Parent.Parent.ui.UISound)

local dispatcher = Networking.client() :: any

export type Snapshot = {
	-- Track id -> branch ("trunk", "a", "b") -> XP.
	masteries: { [string]: { [string]: number } },
	-- Weapon context -> selected profile id.
	shapes: { [string]: string },
}

local ProgressionClient = {}

local snapshot: Snapshot? = nil
local listeners: { [{}]: () -> () } = {}

local NEW_NODE_TAG: { [string]: string } = {
	form = "NEW FORM",
	infusion = "NEW INFUSION",
	passive = "NEW PASSIVE",
	select = "NEW PASSIVE",
}

local function publish()
	for _, listener in pairs(listeners) do
		task.spawn(listener)
	end
end

local function sanitize(raw: any): Snapshot?
	if type(raw) ~= "table" or type(raw.masteries) ~= "table" then
		return nil
	end
	local masteries: { [string]: { [string]: number } } = {}
	for track, entry in pairs(raw.masteries) do
		if type(track) == "string" and type(entry) == "table" and type(entry.branches) == "table" then
			local branches: { [string]: number } = {}
			for branch, xp in pairs(entry.branches) do
				if type(branch) == "string" and type(xp) == "number" then
					branches[branch] = xp
				end
			end
			masteries[track] = branches
		end
	end
	local shapes: { [string]: string } = {}
	if type(raw.shapes) == "table" then
		for classKey, shapeId in pairs(raw.shapes) do
			if type(classKey) == "string" and type(shapeId) == "string" then
				shapes[classKey] = shapeId
			end
		end
	end
	return { masteries = masteries, shapes = shapes }
end

local function announce(previous: Snapshot, current: Snapshot, levelUps: any)
	if type(levelUps) == "table" then
		for _, levelUp in ipairs(levelUps) do
			local track = type(levelUp) == "table" and MasteryTracks.get(levelUp.track)
			if track and type(levelUp.level) == "number" then
				NotificationClient.push({
					tag = "MASTERY UP",
					tone = "success",
					text = `{string.upper(track.displayName)}  LV {levelUp.level}`,
					glyph = track.glyph,
				})
			end
		end
	end

	for _, track in ipairs(MasteryTracks.list()) do
		local tree = MasteryTrees.get(track.id)
		local before = previous.masteries[track.id] or {}
		local after = current.masteries[track.id] or {}
		if tree then
			for _, node in ipairs(tree.nodes) do
				local tag = NEW_NODE_TAG[node.kind]
				if
					tag
					and (node.rank or 0) > 0
					and MasteryTree.isUnlocked(node, after, nil)
					and not MasteryTree.isUnlocked(node, before, nil)
				then
					NotificationClient.push({
						tag = tag,
						tone = "success",
						text = string.upper(node.displayName),
						glyph = track.glyph,
					})
				end
			end
			for _, branch in ipairs({ "trunk", "a", "b" }) do
				if MasteryXP.isMastered(branch, after) and not MasteryXP.isMastered(branch, before) then
					local name = if branch == "trunk" then "TRUNK" else string.upper((tree.branches :: any)[branch])
					NotificationClient.push({
						tag = "MASTERED",
						tone = "success",
						text = `{string.upper(track.displayName)}  {name}`,
						glyph = track.glyph,
					})
				end
			end
		end
	end
end

local function adopt(raw: any)
	local nextSnapshot = sanitize(raw)
	if not nextSnapshot then
		return
	end
	local previous = snapshot
	snapshot = nextSnapshot
	publish()
	-- The first snapshot is where the player already is, not news.
	if previous then
		announce(previous, nextSnapshot, raw.levelUps)
	end
end

function ProgressionClient.get(): Snapshot?
	return snapshot
end

-- A track's XP per branch.
function ProgressionClient.branches(trackId: string): { [string]: number }
	return if snapshot then snapshot.masteries[trackId] or {} else {}
end

function ProgressionClient.level(trackId: string): number
	return MasteryXP.levelOf(MasteryXP.totalOf(ProgressionClient.branches(trackId)))
end

function ProgressionClient.onChanged(callback: () -> ()): () -> ()
	local key = {}
	listeners[key] = callback
	return function()
		listeners[key] = nil
	end
end

-- Ask the server to use `shapeId` for `classKey` ("" for the weapon's default). The server's
-- progression update follows on success.
function ProgressionClient.selectShape(classKey: string, shapeId: string)
	task.spawn(function()
		local ok, response = pcall(function()
			return dispatcher:request("LoadoutSelectShape", { classKey = classKey, shapeId = shapeId })
		end)
		if ok and type(response) == "table" and response.ok then
			UISound.play("confirm")
			return
		end
		UISound.play("error")
		warn("ProgressionClient: shape selection failed:", if ok and type(response) == "table" then response.error else response)
	end)
end

-- Connected before the snapshot request, so an update that lands while it is out is not missed.
dispatcher:on("ProgressionUpdate", adopt)

task.spawn(function()
	local ok, raw = pcall(function()
		return dispatcher:request("ProgressionSnapshot", {})
	end)
	if ok and snapshot == nil then
		adopt(raw)
	end
end)

return ProgressionClient
