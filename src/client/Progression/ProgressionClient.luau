--!strict
-- ProgressionClient: the client's copy of the player's mastery progress and shape selections
-- (server: MasteryService), and the System's announcements when they change.
--
-- The server sends the whole progression whenever any of it changes; this keeps the latest and lets
-- the mastery canvas re-render from it. Selecting a shape goes to the server, which answers with an
-- update rather than this guessing ahead: a selection is a menu action, not a combat one, so a round
-- trip costs nothing the player feels.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Networking = require(ReplicatedStorage.Shared.Networking)
local MasteryTracks = require(ReplicatedStorage.Shared.progression.MasteryTracks)
local BasicAttackProfileRegistry = require(ReplicatedStorage.Shared.skills.BasicAttackProfileRegistry)
local NotificationClient = require(script.Parent.Parent.ui.controllers.NotificationClient)
local UISound = require(script.Parent.Parent.ui.UISound)

local dispatcher = Networking.client() :: any

export type MasteryProgress = { level: number, xp: number }

export type Snapshot = {
	masteries: { [string]: MasteryProgress },
	-- Class key -> selected shape id.
	shapes: { [string]: string },
}

local ProgressionClient = {}

local snapshot: Snapshot? = nil
local listeners: { [{}]: () -> () } = {}

local function publish()
	for _, listener in pairs(listeners) do
		task.spawn(listener)
	end
end

local function sanitize(raw: any): Snapshot?
	if type(raw) ~= "table" or type(raw.masteries) ~= "table" then
		return nil
	end
	local masteries: { [string]: MasteryProgress } = {}
	for track, entry in pairs(raw.masteries) do
		if type(track) == "string" and type(entry) == "table" then
			masteries[track] = {
				level = if type(entry.level) == "number" then entry.level else 0,
				xp = if type(entry.xp) == "number" then entry.xp else 0,
			}
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

-- A level reached is announced, along with any form it opened up.
local function announce(levelUp: any, levels: { [string]: number })
	if type(levelUp) ~= "table" or type(levelUp.level) ~= "number" then
		return
	end
	local track = MasteryTracks.get(levelUp.track)
	if not track then
		return
	end
	NotificationClient.push({
		tag = "MASTERY UP",
		tone = "success",
		text = `{string.upper(track.displayName)}  LV {levelUp.level}`,
		glyph = track.glyph,
	})
	for _, shape in ipairs(BasicAttackProfileRegistry.list()) do
		local required = shape.requires and shape.requires.mastery and shape.requires.mastery[track.id]
		if required == levelUp.level and MasteryTracks.meets(levels, shape.requires) then
			NotificationClient.push({
				tag = "NEW FORM",
				tone = "success",
				text = string.upper(shape.displayName),
				glyph = track.glyph,
			})
		end
	end
end

local function adopt(raw: any)
	local next = sanitize(raw)
	if not next then
		return
	end
	snapshot = next
	publish()
	if type(raw.levelUp) == "table" then
		announce(raw.levelUp, ProgressionClient.levels())
	end
end

function ProgressionClient.get(): Snapshot?
	return snapshot
end

-- Track id -> level, the input MasteryTracks.meets and MasteryTree read.
function ProgressionClient.levels(): { [string]: number }
	local levels: { [string]: number } = {}
	if snapshot then
		for track, entry in pairs(snapshot.masteries) do
			levels[track] = entry.level
		end
	end
	return levels
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
