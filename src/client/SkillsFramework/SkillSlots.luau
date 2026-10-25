--!strict
-- SkillSlots: the client's mirror of the player's skill slot sets, and what fires a slot's skill.
--
-- The server owns the sets and keeps them in the player's save (LoadoutService). Commands apply here
-- first, with the same rules the server uses (LoadoutRules), so assigning a skill or cycling sets in
-- a fight responds at once; the request follows. The server's answer replaces the mirror only once
-- no newer command is still in flight -- otherwise a slow answer to an earlier command would briefly
-- undo a later one. The last answer always carries the full authoritative loadout, so the mirror
-- converges even when the server refuses something it accepted locally.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SkillsClient = require(script.Parent.SkillsClient)
local DebugConfig = require(ReplicatedStorage.Shared.Debug.DebugConfig)
local Networking = require(ReplicatedStorage.Shared.Networking)
local LoadoutTypes = require(ReplicatedStorage.Shared.skills.LoadoutTypes)
local LoadoutRules = require(ReplicatedStorage.Shared.skills.LoadoutRules)

type Loadout = LoadoutTypes.Loadout

-- Temporary diagnostics: activate/release return silently when a slot is empty, which looks
-- identical to a dead keybind. Gated on the existing `inputFlow` flag.
local function logFlow(...: any)
	if DebugConfig.isEnabled("inputFlow") then
		print("[InputFlow]", ...)
	end
end

local dispatcher = Networking.client() :: any

local SkillSlots = {}

export type FilledSlot = { index: number, skill: string }

local loadout: Loadout? = nil
local inFlight = 0

type Callback = (setIndex: number) -> ()
local activeSetChanged: { Callback } = {}
local slotsChanged: { Callback } = {}

local function fire(list: { Callback }, setIndex: number)
	for _, cb in ipairs(list) do
		task.spawn(cb, setIndex)
	end
end

local function subscribe(list: { Callback }, cb: Callback): () -> ()
	table.insert(list, cb)
	return function()
		local index = table.find(list, cb)
		if index then
			table.remove(list, index)
		end
	end
end

local function replace(newLoadout: Loadout)
	local previousActive = loadout and loadout.activeSet
	loadout = newLoadout
	if previousActive ~= newLoadout.activeSet then
		fire(activeSetChanged, newLoadout.activeSet)
	end
	fire(slotsChanged, newLoadout.activeSet)
end

local function adoptServerLoadout(raw: any)
	local sanitized = LoadoutRules.sanitize(raw)
	if sanitized and inFlight == 0 then
		replace(sanitized)
	end
end

local function resync()
	local ok, raw = pcall(function()
		return dispatcher:request("LoadoutSnapshot", {})
	end)
	if ok then
		adoptServerLoadout(raw)
	else
		warn("SkillSlots: loadout snapshot request failed:", raw)
	end
end

local function send(command: LoadoutTypes.LoadoutCommand)
	local current = loadout
	if not current then
		logFlow(`SkillSlots: '{command.kind}' ignored, loadout not loaded yet`)
		return
	end
	local ok, reason = LoadoutRules.apply(current, command)
	if not ok then
		logFlow(`SkillSlots: '{command.kind}' refused locally ({reason})`)
		return
	end
	if command.kind == "setActive" then
		fire(activeSetChanged, current.activeSet)
	end
	fire(slotsChanged, current.activeSet)

	inFlight += 1
	task.spawn(function()
		local requestOk, response = pcall(function()
			return dispatcher:request("LoadoutCommand", command)
		end)
		inFlight -= 1
		if not requestOk or type(response) ~= "table" then
			warn("SkillSlots: LoadoutCommand failed:", response)
			if inFlight == 0 then
				resync()
			end
			return
		end
		if response.ok == false then
			warn(`SkillSlots: server refused '{command.kind}': {response.error}`)
		end
		adoptServerLoadout(response.loadout)
	end)
end

local function activeSlots(): { string }?
	local current = loadout
	if not current then
		return nil
	end
	local set = current.sets[current.activeSet]
	return set and set.slots
end

function SkillSlots.isLoaded(): boolean
	return loadout ~= nil
end

-- The skill in `index` of the active set, or nil when the slot is empty or nothing has loaded.
function SkillSlots.get(index: number): string?
	local slots = activeSlots()
	local skill = slots and slots[index]
	if skill == nil or skill == LoadoutTypes.EMPTY then
		return nil
	end
	return skill
end

-- The active set's filled slots, in slot order.
function SkillSlots.getFilledSlots(): { FilledSlot }
	local list: { FilledSlot } = {}
	local slots = activeSlots()
	if not slots then
		return list
	end
	for index, skill in ipairs(slots) do
		if skill ~= LoadoutTypes.EMPTY then
			table.insert(list, { index = index, skill = skill })
		end
	end
	return list
end

function SkillSlots.activate(index: number)
	local skill = SkillSlots.get(index)
	if not skill then
		logFlow(`activate({index}): NO SKILL in set {SkillSlots.getActiveSet()} (loaded={loadout ~= nil})`)
		return
	end
	logFlow(`activate({index}): -> SkillsClient.useSkill('{skill}')`)
	SkillsClient.useSkill(skill)
end

function SkillSlots.release(index: number)
	local skill = SkillSlots.get(index)
	if not skill then
		logFlow(`release({index}): NO SKILL in set {SkillSlots.getActiveSet()}`)
		return
	end
	logFlow(`release({index}): -> SkillsClient.releaseSkill('{skill}')`)
	SkillsClient.releaseSkill(skill)
end

-- Put `skill` in `slot` of `set` (the active set when omitted), moving it out of any other slot in
-- that set.
function SkillSlots.assign(slot: number, skill: string, set: number?)
	send({ kind = "assign", set = set or SkillSlots.getActiveSet(), slot = slot, skill = skill })
end

function SkillSlots.clear(slot: number, set: number?)
	send({ kind = "clear", set = set or SkillSlots.getActiveSet(), slot = slot })
end

function SkillSlots.setCount(): number
	return if loadout then #loadout.sets else 0
end

function SkillSlots.getActiveSet(): number
	return if loadout then loadout.activeSet else 1
end

function SkillSlots.setActiveSet(set: number)
	if loadout and set == loadout.activeSet then
		return
	end
	send({ kind = "setActive", set = set })
end

function SkillSlots.cycleSet(delta: number?)
	local count = SkillSlots.setCount()
	if count <= 1 then
		return
	end
	local target = (SkillSlots.getActiveSet() - 1 + (delta or 1)) % count + 1
	SkillSlots.setActiveSet(target)
end

function SkillSlots.onActiveSetChanged(cb: Callback): () -> ()
	return subscribe(activeSetChanged, cb)
end

-- Any change to slots, in any set, including the first load.
function SkillSlots.onSlotsChanged(cb: Callback): () -> ()
	return subscribe(slotsChanged, cb)
end

-- Connected before the snapshot request, so a save that finishes loading while the request is out
-- is not missed: whichever arrives first fills the mirror.
dispatcher:on("LoadoutUpdate", function(payload: any)
	if type(payload) == "table" then
		adoptServerLoadout(payload.loadout)
	end
end)

task.spawn(resync)

return SkillSlots
