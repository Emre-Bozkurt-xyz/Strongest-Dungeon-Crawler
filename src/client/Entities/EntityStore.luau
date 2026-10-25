--!strict
-- EntityStore: the client's view of the entities around the player, from EntityInfoService.
--
-- Presence (`EntityInfoDelta`, a few times a second) decides which entities exist here and what
-- the player may know about their health. Vitals (`EntityVitals`, the frame after a pool changes)
-- update the health of entities presence already admitted. Health here is only ever the server's;
-- predicted hits are recorded separately as a strike time, for reactions that must not wait on a
-- round trip, and never touch the value.
--
-- An entity that drops out of presence is kept, not present, for a few seconds, so one flickering at
-- the edge of perception does not tear down and rebuild whatever is drawn for it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Networking = require(ReplicatedStorage.Shared.Networking)
local Registrar = require(script.Parent.Parent.Services.Registrar)

export type Health = {
	-- Exact values when revealed, otherwise only `ratio`.
	current: number?,
	max: number?,
	ratio: number,
}

export type Entry = {
	id: string,
	kind: string,
	name: string,
	-- Nil while the player's perception does not reveal it.
	health: Health?,
	-- The part the entity's UI stands over; nil until its model streams in.
	anchor: BasePart?,
	-- In the latest presence. False while it waits out the grace period.
	present: boolean,
}

type Record = Entry & { lastSeen: number }

local EntityStore = {}

local HIDE_AFTER = 1.0
local DROP_AFTER = 4.0

local records: { [string]: Record } = {}
local struckAt: { [string]: number } = {}
local snapshot: { Entry } = {}
local signature = ""
local listeners: { [{}]: () -> () } = {}
local started = false

local function findAnchor(id: string): BasePart?
	local entity = Registrar.getEntity(id)
	if not entity then
		return nil
	end
	local model = if entity:IsA("Model") then entity else entity.Parent
	local root = model and model:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function healthFrom(item: any): Health?
	local hp = item.hp
	if hp and hp.max > 0 then
		return { current = hp.current, max = hp.max, ratio = math.clamp(hp.current / hp.max, 0, 1) }
	end
	if type(item.hpPerc) == "number" then
		return { ratio = math.clamp(item.hpPerc, 0, 1) }
	end
	return nil
end

-- Only what consumers draw; positions are read live from the anchor.
local function signatureOf(list: { Entry }): string
	local parts = table.create(#list)
	for _, entry in ipairs(list) do
		local health = entry.health
		table.insert(
			parts,
			`{entry.id}:{entry.name}:{entry.present}:{entry.anchor ~= nil}:`
				.. (if health then `{health.current or ""}/{health.max or ""}/{math.floor(health.ratio * 1000)}` else "-")
		)
	end
	return table.concat(parts, "\n")
end

local function publish()
	local list: { Entry } = {}
	for _, record in pairs(records) do
		table.insert(list, {
			id = record.id,
			kind = record.kind,
			name = record.name,
			health = record.health,
			anchor = record.anchor,
			present = record.present,
		})
	end
	table.sort(list, function(a, b)
		return a.id < b.id
	end)
	local nextSignature = signatureOf(list)
	if nextSignature == signature then
		return
	end
	signature = nextSignature
	snapshot = list
	for _, listener in pairs(listeners) do
		task.spawn(listener)
	end
end

local function refreshAnchor(record: Record)
	if not (record.anchor and record.anchor.Parent) then
		record.anchor = findAnchor(record.id)
	end
end

local function onPresence(payload: any)
	if type(payload) ~= "table" or type(payload.items) ~= "table" then
		return
	end
	local now = os.clock()
	for _, item in ipairs(payload.items) do
		local record = records[item.id]
		if not record then
			record = { id = item.id, kind = item.kind, name = item.name, present = true, lastSeen = now }
			records[item.id] = record
		end
		record.kind = item.kind
		record.name = item.name
		record.health = healthFrom(item)
		record.present = true
		record.lastSeen = now
		refreshAnchor(record)
	end
	for id, record in pairs(records) do
		local absent = now - record.lastSeen
		if absent > DROP_AFTER then
			records[id] = nil
			struckAt[id] = nil
		elseif absent > HIDE_AFTER then
			record.present = false
		end
	end
	publish()
end

local function onVitals(payload: any)
	if type(payload) ~= "table" or type(payload.items) ~= "table" then
		return
	end
	for _, item in ipairs(payload.items) do
		local record = records[item.id]
		if record then
			record.health = healthFrom(item)
			refreshAnchor(record)
		end
	end
	publish()
end

function EntityStore.start()
	if started then
		return
	end
	started = true
	local dispatcher = Networking.client() :: any
	dispatcher:on("EntityInfoDelta", onPresence)
	dispatcher:on("EntityVitals", onVitals)
end

function EntityStore.get(id: string): Entry?
	return records[id]
end

-- False only when the server has revealed this entity at zero health; unknown counts as alive.
function EntityStore.isAlive(id: string): boolean
	local record = records[id]
	local health = record and record.health
	return not health or health.ratio > 0
end

function EntityStore.getSnapshot(): { Entry }
	return snapshot
end

function EntityStore.onChanged(callback: () -> ()): () -> ()
	local token = {}
	listeners[token] = callback
	return function()
		listeners[token] = nil
	end
end

-- A local, predicted hit on `id`. Read per frame by whatever reacts to it.
function EntityStore.markStruck(id: string)
	struckAt[id] = os.clock()
end

function EntityStore.getStruckAt(id: string): number?
	return struckAt[id]
end

return EntityStore
