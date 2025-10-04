--!strict
-- SkillSlots: Multi-profile skill slot management.
-- A "profile" (aka skill set) is an independent sparse array mapping slot index -> skillName.
-- Player starts with 1 profile (default shows Punch in slot 1). Additional profiles can be unlocked.
-- Profiles can be cycled (e.g., via LeftAlt) with no cooldown restrictions.
-- Sparse design: slot indices do NOT need to be contiguous; UI should only render filled slots.
-- NOTE: Previous logicalSize hint removed; profiles are purely sparse maps now.
-- API:
--   SkillSlots.createProfile(initialSlotCount?: number) -> profileId
--   SkillSlots.unlockProfile(initialSlotCount?: number) -> profileId (alias)
--   SkillSlots.cycleProfile(delta?: number) -- default delta=1 forward
--   SkillSlots.getActiveProfileId() -> number
--   SkillSlots.setActiveProfile(profileId: number)
--   (Deprecated) SkillSlots.setSlotCount(n) -- now no-op except firing slotsChanged (legacy compatibility)
--   SkillSlots.assign(slotIndex, skillName)
--   SkillSlots.clear(slotIndex)
--   SkillSlots.get(slotIndex) -> string?
--   SkillSlots.getAll() -> {string?} (deprecated dense list of filled skills only)
--   SkillSlots.getFilledSlots() -> { { index, skill } }
--   SkillSlots.serialize() -> serialized table
--   SkillSlots.load(dataTable)
--   SkillSlots.activate(slotIndex)
--   SkillSlots.profileCount() -> number
--   SkillSlots.onProfileChanged(cb(profileId)) -> () -> ()
--   SkillSlots.onSlotsChanged(cb(profileId)) -> () -> ()  -- any assign/clear/resize in that profile
-- Future extension: persistence (serialize/deserialize), per-slot metadata (cooldowns, icons), profile naming.
-- Dependencies kept minimal: only requires SkillsClient to actually fire skill usage.

local SkillsClient = require(script.Parent.SkillsClient)

local SkillSlots = {}

-- Internal structures
type SlotArray = { [number]: string? }

local profiles: { [number]: { slots: SlotArray } } = {}
local activeProfile = 1
local nextProfileId = 1

-- Event signal helpers (lightweight custom)
type Callback<T...> = (T...) -> ()
local profileChanged: { Callback<number> } = {}
local slotsChanged: { Callback<number> } = {}

local function fire(list: { any }, ...: any)
	for _, cb in ipairs(list) do
		task.spawn(cb, ...)
	end
end

local function ensureProfile(id: number)
	local p = profiles[id]
	if not p then
		p = { slots = {} }
		profiles[id] = p
	end
	return p
end

local function createProfileInternal(): number
	local id = nextProfileId
	nextProfileId += 1
	ensureProfile(id)
	return id
end

function SkillSlots.assign(index: number, skillName: string)
	if index < 1 then
		error("SkillSlots.assign: index < 1")
	end
	local p = ensureProfile(activeProfile)
	p.slots[index] = skillName
	fire(slotsChanged, activeProfile)
end

function SkillSlots.clear(index: number)
	local p = profiles[activeProfile]
	if not p then return end
	if index < 1 then return end
	if p.slots[index] == nil then return end
	p.slots[index] = nil
	fire(slotsChanged, activeProfile)
end

function SkillSlots.get(index: number): string?
	local p = profiles[activeProfile]
	if not p then return nil end
	if index < 1 then return nil end
	return p.slots[index]
end

-- Deprecated: getAll with contiguous empty slots; kept for backward compatibility returning a dense array of filled entries only.
function SkillSlots.getAll(): {string?}
	local p = profiles[activeProfile]
	local out: {string?} = {}
	if not p then return out end
	-- Collect filled slots only (order by index ascending)
	local indices: {number} = {}
	for idx, skill in pairs(p.slots) do
		if type(idx) == "number" and skill ~= nil then
			table.insert(indices, idx)
		end
	end
	table.sort(indices)
	for i, slotIndex in ipairs(indices) do
		out[i] = p.slots[slotIndex]
	end
	return out
end

-- Preferred: explicit filled slot enumeration preserving actual indices.
export type FilledSlot = { index: number, skill: string }
function SkillSlots.getFilledSlots(): { FilledSlot }
	local p = profiles[activeProfile]
	local list: { FilledSlot } = {}
	if not p then return list end
	for idx, skill in pairs(p.slots) do
		if type(idx) == "number" and skill ~= nil then
			table.insert(list, { index = idx, skill = skill :: string })
		end
	end
	table.sort(list, function(a, b)
		return a.index < b.index
	end)
	return list
end

function SkillSlots.activate(index: number)
	local skill = SkillSlots.get(index)
	if not skill then return end
	SkillsClient.useSkill(skill)
end

function SkillSlots.profileCount(): number
	return nextProfileId - 1
end

function SkillSlots.getActiveProfileId(): number
	return activeProfile
end

function SkillSlots.setActiveProfile(id: number)
	if id == activeProfile then return end
	if not profiles[id] then return end
	activeProfile = id
	fire(profileChanged, activeProfile)
end

function SkillSlots.cycleProfile(delta: number?)
	delta = delta or 1
	local count = SkillSlots.profileCount()
	if count <= 1 then return end
	local d = delta :: number
	local target = activeProfile + d
	if target < 1 then
		target = count
	elseif target > count then
		target = 1
	end
	SkillSlots.setActiveProfile(target)
end

function SkillSlots.createProfile(): number
	local id = createProfileInternal()
	fire(profileChanged, activeProfile) -- slight nudge so UI can know total count changed
	return id
end

SkillSlots.unlockProfile = SkillSlots.createProfile

function SkillSlots.onProfileChanged(cb: (number) -> ())
	table.insert(profileChanged, cb)
	return function()
		for i, f in ipairs(profileChanged) do
			if f == cb then
				table.remove(profileChanged, i)
				break
			end
		end
	end
end

function SkillSlots.onSlotsChanged(cb: (number) -> ())
	table.insert(slotsChanged, cb)
	return function()
		for i, f in ipairs(slotsChanged) do
			if f == cb then
				table.remove(slotsChanged, i)
				break
			end
		end
	end
end

-- Bootstrap: create initial profile 1 and set defaults
createProfileInternal()
SkillSlots.setActiveProfile(1)
SkillSlots.assign(1, "Punch")
SkillSlots.assign(2, "TripleStrike")

-- Public: explicit API to expand beyond default 5 via assign or setSlotCount.

-- Serialization / Deserialization
-- Shape:
-- {
--   active = number,
--   profiles = {
--       [id] = { slots = { [slotIndex] = skillName } }
--   }
-- }

function SkillSlots.serialize(): { [string]: any }
	local dataProfiles: { [number]: any } = {}
	for id, prof in pairs(profiles) do
		local copySlots: { [number]: string } = {}
		for idx, skill in pairs(prof.slots) do
			if skill then
				copySlots[idx] = skill
			end
		end
		dataProfiles[id] = { slots = copySlots }
	end
	return {
		active = activeProfile,
		profiles = dataProfiles,
	}
end

function SkillSlots.load(data: any)
	if type(data) ~= "table" then return end
	if type(data.profiles) ~= "table" then return end
	profiles = {}
	nextProfileId = 1
	for id, prof in pairs(data.profiles) do
		if type(id) == "number" and type(prof) == "table" then
			local newId = id
			if newId >= nextProfileId then
				nextProfileId = newId + 1
			end
			local slotMap: SlotArray = {}
			local slotSrc = prof.slots
			if type(slotSrc) == "table" then
				for sIdx, sName in pairs(slotSrc) do
					if type(sIdx) == "number" and type(sName) == "string" then
						slotMap[sIdx] = sName
					end
				end
			end
			profiles[newId] = { slots = slotMap }
		end
	end
	if type(data.active) == "number" and profiles[data.active] then
		activeProfile = data.active
	else
		activeProfile = 1
	end
	fire(profileChanged, activeProfile)
	fire(slotsChanged, activeProfile)
end

-- Cooldown stubs (future expansion): You can layer a cooldown tracker keyed by skill or by (profile, slotIndex).
-- Placeholder API for future integration.
function SkillSlots.getCooldown(slotIndex: number): number?
	slotIndex = slotIndex
	return nil
end

function SkillSlots.setCooldown(slotIndex: number, _remaining: number)
	slotIndex = slotIndex
	-- Intentionally no-op for now.
end

return SkillSlots
