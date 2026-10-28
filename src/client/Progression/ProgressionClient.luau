--!strict
-- ProgressionClient: the client's copy of the player's progression -- character XP, mastery
-- progress, attunement, and form and infusion selections (server: ProgressionSync) -- and the
-- System's announcements when they change.
--
-- The server sends the whole progression -- character XP, XP per track and branch, and the selected
-- form per weapon context -- whenever any of it changes; this keeps the latest and lets the STATUS
-- panel and the mastery canvas re-render from it. Selecting a form goes to the server, which answers with an update rather than
-- this guessing ahead: a selection is a menu action, not a combat one, so a round trip costs nothing
-- the player feels.
--
-- Announcements: the levels the server marks as reached (character and mastery), and, by comparing
-- each update with the last, any node that opened, branch that was Mastered, attunement slot that
-- opened or track that was attuned or released since.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Networking = require(ReplicatedStorage.Shared.Networking)
local MasteryTracks = require(ReplicatedStorage.Shared.progression.MasteryTracks)
local MasteryTrees = require(ReplicatedStorage.Shared.progression.MasteryTrees)
local MasteryTree = require(ReplicatedStorage.Shared.progression.MasteryTree)
local MasteryXP = require(ReplicatedStorage.Shared.progression.MasteryXP)
local CharacterXP = require(ReplicatedStorage.Shared.progression.CharacterXP)
local Attunement = require(ReplicatedStorage.Shared.progression.Attunement)
local PassivePool = require(ReplicatedStorage.Shared.progression.PassivePool)
local NotificationClient = require(script.Parent.Parent.ui.controllers.NotificationClient)
local UISound = require(script.Parent.Parent.ui.UISound)

local dispatcher = Networking.client() :: any

export type Snapshot = {
	-- Total character XP; the level is derived from it (CharacterXP).
	characterXp: number,
	-- Track id -> branch ("trunk", "a", "b") -> XP.
	masteries: { [string]: { [string]: number } },
	-- Weapon context -> selected profile id.
	shapes: { [string]: string },
	-- Selected infusion node id, or "" for none.
	infusion: string,
	-- Chosen selectable passive node ids, in the order chosen (before cutting to the slots).
	passives: { string },
	-- Attuned track ids, in the order they were attuned.
	attunement: { string },
	-- Unlocked node ids the player has not looked at yet.
	unseen: { [string]: boolean },
}

local ProgressionClient = {}

local snapshot: Snapshot? = nil
local listeners: { [{}]: () -> () } = {}

-- What the server's refusal of a selectable passive means to the player.
local PASSIVE_FAILURES: { [string]: string } = {
	locked = "NOT AVAILABLE",
}

-- What the server's refusal of an attunement change means to the player.
local ATTUNE_FAILURES: { [string]: string } = {
	no_free_slot = "NO FREE SLOT",
	not_at_shrine = "TOO FAR FROM THE SHRINE",
}

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
	local attunement: { string } = {}
	if type(raw.attunement) == "table" then
		for _, trackId in ipairs(raw.attunement) do
			if type(trackId) == "string" then
				table.insert(attunement, trackId)
			end
		end
	end
	local character = raw.character
	local characterXp = if type(character) == "table" and type(character.xp) == "number" then character.xp else 0
	local infusion = if type(raw.infusion) == "string" then raw.infusion else ""
	local passives: { string } = {}
	if type(raw.passives) == "table" then
		for _, nodeId in ipairs(raw.passives) do
			if type(nodeId) == "string" then
				table.insert(passives, nodeId)
			end
		end
	end
	local unseen: { [string]: boolean } = {}
	if type(raw.unseen) == "table" then
		for _, nodeId in ipairs(raw.unseen) do
			if type(nodeId) == "string" then
				unseen[nodeId] = true
			end
		end
	end
	return {
		characterXp = characterXp,
		masteries = masteries,
		shapes = shapes,
		infusion = infusion,
		passives = passives,
		attunement = attunement,
		unseen = unseen,
	}
end

local function announce(previous: Snapshot, current: Snapshot, events: any)
	if type(events) == "table" then
		for _, event in ipairs(events) do
			if type(event) ~= "table" or type(event.level) ~= "number" then
				continue
			end
			if event.kind == "characterLevel" then
				NotificationClient.push({
					tag = "LEVEL UP",
					tone = "success",
					text = if type(event.points) == "number"
						then `LV {event.level}  ·  +{event.points} POINTS`
						else `LV {event.level}`,
				})
				local before = CharacterXP.levelOf(previous.characterXp)
				if Attunement.slotsFor(event.level) > Attunement.slotsFor(before) then
					NotificationClient.push({
						tag = "NEW ATTUNEMENT SLOT",
						tone = "success",
						text = "VISIT AN ATTUNEMENT SHRINE",
					})
				end
			elseif event.kind == "masteryLevel" then
				local track = MasteryTracks.get(event.track)
				if track then
					NotificationClient.push({
						tag = "MASTERY UP",
						tone = "success",
						text = `{string.upper(track.displayName)}  LV {event.level}`,
						glyph = track.glyph,
					})
				end
			end
		end
	end

	for _, track in ipairs(MasteryTracks.list()) do
		local wasAttuned = table.find(previous.attunement, track.id) ~= nil
		local isAttuned = table.find(current.attunement, track.id) ~= nil
		if wasAttuned ~= isAttuned then
			NotificationClient.push({
				tag = if isAttuned then "ATTUNED" else "RELEASED",
				tone = if isAttuned then "success" else "info",
				text = string.upper(track.displayName),
				glyph = track.glyph,
			})
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
		announce(previous, nextSnapshot, raw.events)
	end
end

function ProgressionClient.get(): Snapshot?
	return snapshot
end

function ProgressionClient.characterProgress(): CharacterXP.Progress
	return CharacterXP.progressOf(if snapshot then snapshot.characterXp else 0)
end

-- A track's XP per branch.
function ProgressionClient.branches(trackId: string): { [string]: number }
	return if snapshot then snapshot.masteries[trackId] or {} else {}
end

function ProgressionClient.level(trackId: string): number
	return MasteryXP.levelOf(MasteryXP.totalOf(ProgressionClient.branches(trackId)))
end

function ProgressionClient.isAttuned(trackId: string): boolean
	return snapshot ~= nil and table.find(snapshot.attunement, trackId) ~= nil
end

function ProgressionClient.attunement(): { string }
	return if snapshot then snapshot.attunement else {}
end

-- How many tracks the character may attune at their level.
function ProgressionClient.attunementSlots(): number
	return Attunement.slotsFor(ProgressionClient.characterProgress().level)
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

-- Ask the server to use the infusion `infusionId` (a node id), or "" for none. The server's
-- progression update follows on success.
function ProgressionClient.selectInfusion(infusionId: string)
	task.spawn(function()
		local ok, response = pcall(function()
			return dispatcher:request("LoadoutSelectInfusion", { infusionId = infusionId })
		end)
		if ok and type(response) == "table" and response.ok then
			UISound.play("confirm")
			return
		end
		UISound.play("error")
		warn(
			"ProgressionClient: infusion selection failed:",
			if ok and type(response) == "table" then response.error else response
		)
	end)
end

-- How many selectable passives the character may have chosen at their level, and the level that
-- opens the next slot (nil once all are open).
function ProgressionClient.passiveSlots(): (number, number?)
	local level = ProgressionClient.characterProgress().level
	local slots = PassivePool.slotsFor(level)
	return slots, PassivePool.SLOT_LEVELS[slots + 1]
end

-- The chosen selectable passives that have a slot, by the server's rule (PassiveService.chosenOf).
function ProgressionClient.chosenPassives(): { string }
	local out: { string } = {}
	if not snapshot then
		return out
	end
	local slots = ProgressionClient.passiveSlots()
	for _, nodeId in ipairs(snapshot.passives) do
		if #out >= slots then
			break
		end
		table.insert(out, nodeId)
	end
	return out
end

-- Ask the server to choose the selectable passive `nodeId`, or drop it. The server's progression
-- update follows on success.
function ProgressionClient.selectPassive(nodeId: string, selected: boolean)
	task.spawn(function()
		local ok, response = pcall(function()
			return dispatcher:request("ProgressionSelectPassive", { nodeId = nodeId, selected = selected })
		end)
		if ok and type(response) == "table" and response.ok then
			UISound.play("confirm")
			return
		end
		UISound.play("error")
		local reason = if ok and type(response) == "table" then response.error else nil
		if reason == "no_free_slot" then
			local slots, nextAt = ProgressionClient.passiveSlots()
			NotificationClient.push({
				tag = "NO FREE SLOT",
				tone = "warning",
				text = if nextAt then `{slots} PASSIVE SLOTS  ·  NEXT AT LV {nextAt}` else `{slots} PASSIVE SLOTS IN USE`,
				key = "passive:no_free_slot",
			})
		elseif reason and PASSIVE_FAILURES[reason] then
			NotificationClient.push({
				tag = "CANNOT CHOOSE",
				tone = "warning",
				text = PASSIVE_FAILURES[reason],
				key = `passive:{reason}`,
			})
		else
			warn("ProgressionClient: passive selection failed:", reason or response)
		end
	end)
end

-- Ask the server to attune `trackId`, or release it. Only accepted at a shrine; the progression
-- update follows on success.
function ProgressionClient.setAttuned(trackId: string, attuned: boolean)
	task.spawn(function()
		local ok, response = pcall(function()
			return dispatcher:request("ProgressionAttune", { track = trackId, attuned = attuned })
		end)
		if ok and type(response) == "table" and response.ok then
			UISound.play("confirm")
			return
		end
		UISound.play("error")
		local reason = if ok and type(response) == "table" then response.error else nil
		local text = reason and ATTUNE_FAILURES[reason]
		if text then
			NotificationClient.push({ tag = "CANNOT ATTUNE", tone = "warning", text = text, key = `attune:{reason}` })
		else
			warn("ProgressionClient: attunement change failed:", reason or response)
		end
	end)
end

-- Whether a node unlocked since the player last looked at it.
function ProgressionClient.isUnseen(nodeId: string): boolean
	return snapshot ~= nil and snapshot.unseen[nodeId] == true
end

-- The player has looked at `nodeId`. Cleared here at once so the mark stops without waiting on the
-- server, which saves it.
function ProgressionClient.markSeen(nodeId: string)
	if not snapshot or not snapshot.unseen[nodeId] then
		return
	end
	-- A new snapshot rather than an edit, so subscribers comparing by reference see the change.
	local unseen = table.clone(snapshot.unseen)
	unseen[nodeId] = nil
	local nextSnapshot = table.clone(snapshot)
	nextSnapshot.unseen = unseen
	snapshot = nextSnapshot
	publish()
	task.spawn(function()
		pcall(function()
			return dispatcher:request("ProgressionSeen", { nodeIds = { nodeId } })
		end)
	end)
end

-- Ask the server to release `release` and attune `trackId` in its place, as one change.
function ProgressionClient.swapAttuned(release: string, trackId: string)
	task.spawn(function()
		local ok, response = pcall(function()
			return dispatcher:request("ProgressionAttune", { track = trackId, release = release })
		end)
		if ok and type(response) == "table" and response.ok then
			UISound.play("confirm")
			return
		end
		UISound.play("error")
		local reason = if ok and type(response) == "table" then response.error else nil
		local text = reason and ATTUNE_FAILURES[reason]
		if text then
			NotificationClient.push({ tag = "CANNOT ATTUNE", tone = "warning", text = text, key = `attune:{reason}` })
		else
			warn("ProgressionClient: attunement swap failed:", reason or response)
		end
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
