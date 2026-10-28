--!strict
-- How a loadout command changes a loadout, read the same way by both peers.
--
-- The client applies a command here immediately so the change feels instant; the server applies the
-- same command here to its own copy. Shared rules are what let the client's guess match the answer
-- it gets back. The server adds the checks only it can make (does the player own the skill) before
-- calling `apply`.
--
-- Both peers also pass the limits the character's level sets (LoadoutUnlocks): a locked slot or set
-- cannot be changed or made active, though what the save holds there is kept.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LoadoutTypes = require(ReplicatedStorage.Shared.skills.LoadoutTypes)
local LoadoutUnlocks = require(ReplicatedStorage.Shared.skills.LoadoutUnlocks)

type Loadout = LoadoutTypes.Loadout
type Limits = LoadoutUnlocks.Limits

local SLOTS_PER_SET = LoadoutTypes.SLOTS_PER_SET
local EMPTY = LoadoutTypes.EMPTY
local MAX_SKILL_NAME_LENGTH = LoadoutTypes.MAX_SKILL_NAME_LENGTH
local MAX_SETS = LoadoutTypes.MAX_SETS

local LoadoutRules = {}

-- Rejects NaN, infinities and fractions as well as non-numbers: every index here comes off the wire.
local function isIndex(value: any, max: number): boolean
	return type(value) == "number" and value == math.floor(value) and value >= 1 and value <= max
end

local function isSkillName(value: any): boolean
	return type(value) == "string" and #value > 0 and #value <= MAX_SKILL_NAME_LENGTH
end

-- A well-formed copy of `raw`, or nil when it is not a usable loadout at all. Individual bad entries
-- (a non-string slot, an out-of-range active set) are repaired rather than failing the whole thing,
-- so one corrupt slot in a save does not cost the player every other assignment.
function LoadoutRules.sanitize(raw: any): Loadout?
	if type(raw) ~= "table" or type(raw.sets) ~= "table" then
		return nil
	end

	local sets: { LoadoutTypes.SlotSet } = {}
	for index, rawSet in ipairs(raw.sets) do
		if index > MAX_SETS then
			break
		end
		local rawSlots = type(rawSet) == "table" and rawSet.slots or nil
		local slots: { string } = {}
		for slot = 1, SLOTS_PER_SET do
			local value = type(rawSlots) == "table" and rawSlots[slot] or nil
			slots[slot] = if isSkillName(value) then value else EMPTY
		end
		table.insert(sets, { slots = slots })
	end
	if #sets == 0 then
		return nil
	end
	-- A save from before sets opened with level may hold fewer.
	while #sets < MAX_SETS do
		local slots: { string } = {}
		for slot = 1, SLOTS_PER_SET do
			slots[slot] = EMPTY
		end
		table.insert(sets, { slots = slots })
	end

	return {
		activeSet = if isIndex(raw.activeSet, #sets) then raw.activeSet else 1,
		sets = sets,
	}
end

-- The set the character fights with: the saved active set, unless the level does not open it (a
-- milestone retuned upward), in which case the first.
function LoadoutRules.activeSet(loadout: Loadout, limits: Limits): number
	return if loadout.activeSet <= limits.sets then loadout.activeSet else 1
end

-- Apply `command` to `loadout` in place. Returns false and a reason, leaving `loadout` untouched,
-- when the command is malformed, out of range, or reaches a slot or set the level has not opened.
function LoadoutRules.apply(loadout: Loadout, command: any, limits: Limits): (boolean, string?)
	if type(command) ~= "table" then
		return false, "invalid_command"
	end
	local setCount = #loadout.sets
	if not isIndex(command.set, setCount) then
		return false, "invalid_set"
	end
	if command.set > limits.sets then
		return false, "set_locked"
	end
	local set = loadout.sets[command.set]

	if command.kind == "setActive" then
		loadout.activeSet = command.set
		return true, nil
	end

	if not isIndex(command.slot, SLOTS_PER_SET) then
		return false, "invalid_slot"
	end
	if command.slot > limits.slots then
		return false, "slot_locked"
	end

	if command.kind == "clear" then
		set.slots[command.slot] = EMPTY
		return true, nil
	end

	if command.kind == "assign" then
		if not isSkillName(command.skill) then
			return false, "invalid_skill"
		end
		-- A skill sits in at most one slot of a set: assigning it elsewhere moves it, and whatever
		-- held the target takes its old place, so moving a skill never drops another off the bar.
		local displaced = set.slots[command.slot]
		for slot, skill in ipairs(set.slots) do
			if skill == command.skill then
				set.slots[slot] = displaced
			end
		end
		set.slots[command.slot] = command.skill
		return true, nil
	end

	return false, "unknown_command"
end

return LoadoutRules
