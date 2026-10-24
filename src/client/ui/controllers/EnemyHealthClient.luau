--!strict
-- EnemyHealthClient: which entities' health is revealed to the player, from EntityRevealStore's
-- presence feed, for the bars over their heads (panels/EnemyBars).
--
-- An entity shows while the server reports it with health -- exact (`hp`) or only a percentage
-- (`hpPerc`), depending on what the player has revealed. It is kept, hidden, for a few seconds after
-- it drops out of the feed, so a bar that flickers out of presence does not tear down and rebuild.

local EntityRevealStore = require(script.Parent.Parent.Parent.EntityRevealStore)
local Registrar = require(script.Parent.Parent.Parent.Services.Registrar)

export type Entry = {
	id: string,
	name: string,
	-- Exact health when revealed, otherwise a 0..1 fraction.
	current: number?,
	max: number?,
	ratio: number,
	-- The part the bar stands over; nil until the entity's model streams in.
	anchor: BasePart?,
	-- Reported in the latest presence update. False while it waits out the grace period.
	present: boolean,
}

local EnemyHealthClient = {}

-- Seconds without presence before a bar hides, then before it is dropped.
local HIDE_AFTER = 1.0
local DROP_AFTER = 4.0

local entries: { [string]: Entry & { lastSeen: number } } = {}
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

-- Only what the bars draw; positions change every update and are read live from the anchor.
local function signatureOf(list: { Entry }): string
	local parts = table.create(#list)
	for _, entry in ipairs(list) do
		table.insert(
			parts,
			`{entry.id}:{entry.name}:{entry.current or ""}:{entry.max or ""}:{math.floor(entry.ratio * 1000)}:{entry.present}:{entry.anchor ~= nil}`
		)
	end
	return table.concat(parts, "\n")
end

local function publish()
	local list: { Entry } = {}
	for _, entry in pairs(entries) do
		table.insert(list, {
			id = entry.id,
			name = entry.name,
			current = entry.current,
			max = entry.max,
			ratio = entry.ratio,
			anchor = entry.anchor,
			present = entry.present,
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

local function onPresence(payload: any)
	local now = os.clock()
	for _, item in ipairs(payload.items) do
		local hp = item.hp
		if not hp and item.hpPerc == nil then
			-- Health no longer revealed.
			entries[item.id] = nil
			continue
		end
		local entry = entries[item.id]
		if not entry then
			entry = { id = item.id, name = item.name, ratio = 1, present = true, lastSeen = now }
			entries[item.id] = entry
		end
		entry.name = item.name
		entry.current = if hp then hp.current else nil
		entry.max = if hp then hp.max else nil
		entry.ratio = if hp and hp.max > 0 then math.clamp(hp.current / hp.max, 0, 1) else math.clamp(item.hpPerc or 0, 0, 1)
		entry.anchor = if entry.anchor and entry.anchor.Parent then entry.anchor else findAnchor(item.id)
		entry.present = true
		entry.lastSeen = now
	end
	for id, entry in pairs(entries) do
		local absent = now - entry.lastSeen
		if absent > DROP_AFTER then
			entries[id] = nil
		elseif absent > HIDE_AFTER then
			entry.present = false
		end
	end
	publish()
end

function EnemyHealthClient.start()
	if started then
		return
	end
	started = true
	EntityRevealStore.start()
	EntityRevealStore.onPresence(onPresence)
end

function EnemyHealthClient.getSnapshot(): { Entry }
	return snapshot
end

function EnemyHealthClient.onChanged(callback: () -> ()): () -> ()
	local token = {}
	listeners[token] = callback
	return function()
		listeners[token] = nil
	end
end

return EnemyHealthClient
