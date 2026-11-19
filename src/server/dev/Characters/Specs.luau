--!strict
-- Character specs as data: resolving `extends`, checking a whole spec against the game's real
-- content, and building the stand-in save it describes. Nothing here touches a player; Characters
-- puts the result on one.
--
-- Validation reports every problem it finds rather than stopping at the first, so a preset can be
-- fixed in one pass. It checks what the save would silently drop or ignore -- an attunement over the
-- level's slots, a locked infusion, a skill on the bar the character does not own -- since a spec
-- that quietly does less than it says is worse than one that fails.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local AttributeTypes = require(ReplicatedStorage.Shared.AttributeTypes)
local StatTypes = require(ReplicatedStorage.Shared.StatTypes)
local CharacterXP = require(ReplicatedStorage.Shared.progression.CharacterXP)
local MasteryXP = require(ReplicatedStorage.Shared.progression.MasteryXP)
local MasteryTracks = require(ReplicatedStorage.Shared.progression.MasteryTracks)
local MasteryTrees = require(ReplicatedStorage.Shared.progression.MasteryTrees)
local MasteryTree = require(ReplicatedStorage.Shared.progression.MasteryTree)
local Attunement = require(ReplicatedStorage.Shared.progression.Attunement)
local PassivePool = require(ReplicatedStorage.Shared.progression.PassivePool)
local LoadoutTypes = require(ReplicatedStorage.Shared.skills.LoadoutTypes)
local BasicAttackProfileRegistry = require(ReplicatedStorage.Shared.skills.BasicAttackProfileRegistry)
local Registry = require(ReplicatedStorage.Shared.items.Registry)
local ItemEnums = require(ReplicatedStorage.Shared.items.ItemEnums)
local EquipmentDefUtils = require(ReplicatedStorage.Shared.items.EquipmentDefUtils)

local Server = ServerScriptService.Server
local PlayerDataSchema = require(Server.PlayerData.PlayerDataSchema)
local SkillsConfig = require(Server.SkillsFramework.SkillsConfig)
local StatsConfig = require(Server.Stats.Config.StatsConfig)
local AttributesConfig = require(Server.Stats.Config.AttributesConfig)
local ItemInstances = require(Server.Inventory.ItemInstances)
local AffixRollService = require(Server.Inventory.Generation.AffixRollService)
local Types = require(script.Parent.Types)

type Spec = Types.Spec
type PlayerSaveData = PlayerDataSchema.PlayerSaveData

local Specs = {}

local FIELDS: { [string]: boolean } = {
	extends = true,
	level = true,
	xp = true,
	attributes = true,
	mastery = true,
	attuned = true,
	skills = true,
	bar = true,
	activeSet = true,
	equipment = true,
	bag = true,
	capacity = true,
	shapes = true,
	infusion = true,
	passives = true,
	pools = true,
	stats = true,
}

local BRANCHES = { "trunk", "a", "b" }
local RARITIES: { [string]: boolean } = { normal = true, magic = true, rare = true, unique = true }
local DEFAULT_CAPACITY = PlayerDataSchema.template().inventory.capacity
local MAX_CAPACITY = 200

local POOLS: { [string]: boolean } = {}
for _, pool in pairs(StatTypes.PoolStats) do
	POOLS[pool] = true
end

local function isMap(value: any): boolean
	if type(value) ~= "table" or next(value) == nil then
		return false
	end
	for key in pairs(value) do
		if type(key) ~= "string" then
			return false
		end
	end
	return true
end

local function isList(value: any): boolean
	if type(value) ~= "table" then
		return false
	end
	local count = 0
	for _ in pairs(value) do
		count += 1
	end
	return count == #value
end

local function isWhole(value: any): boolean
	return type(value) == "number" and value == math.floor(value) and value == value
end

function Specs.deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for key, child in pairs(value) do
		out[Specs.deepCopy(key)] = Specs.deepCopy(child)
	end
	return out
end

-- `over` laid on `base`, by the rules in Types.
function Specs.merge(base: { [any]: any }, over: { [any]: any }): { [any]: any }
	local out = Specs.deepCopy(base)
	for key, value in pairs(over) do
		if value == false then
			out[key] = nil
		elseif isMap(value) and isMap(out[key]) then
			out[key] = Specs.merge(out[key], value)
		else
			out[key] = Specs.deepCopy(value)
		end
	end
	return out
end

-- The spec with every `extends` applied. `getPreset` returns a preset's own, unresolved spec.
function Specs.resolve(spec: any, getPreset: (name: string) -> any?, chain: { string }?): (Spec?, string?)
	if type(spec) ~= "table" then
		return nil, `a spec must be a table, got {typeof(spec)}`
	end
	local parentName = spec.extends
	if parentName == nil then
		local out = Specs.deepCopy(spec)
		out.extends = nil
		return out, nil
	end
	if type(parentName) ~= "string" then
		return nil, "extends must be a preset name"
	end
	local seen = chain or {}
	if table.find(seen, parentName) then
		return nil, `extends cycle: {table.concat(seen, " -> ")} -> {parentName}`
	end
	local parentRaw = getPreset(parentName)
	if parentRaw == nil then
		return nil, `extends unknown preset '{parentName}'`
	end
	local nextChain = table.clone(seen)
	table.insert(nextChain, parentName)
	local parent, err = Specs.resolve(parentRaw, getPreset, nextChain)
	if not parent then
		return nil, err
	end
	local merged = Specs.merge(parent, spec)
	merged.extends = nil
	return merged :: Spec, nil
end

local function itemIdOf(item: any): any
	return if type(item) == "table" then item[1] else item
end

local function countOf(item: any): any
	if type(item) ~= "table" then
		return 1
	end
	return item.count or item[2] or 1
end

local function stackLimitOf(def: any): number
	return if def.stackLimit and def.stackLimit > 0 then def.stackLimit else 1
end

local function contains(list: { any }?, value: any): boolean
	return list ~= nil and table.find(list, value) ~= nil
end

-- Whether the item may go in `slot`, by the same rules the equip validator applies to slots.
local function slotAllowed(def: any, slot: string): boolean
	if not contains(EquipmentDefUtils.getEquipSlots(def), slot) then
		return false
	end
	local weapon = EquipmentDefUtils.getWeapon(def)
	if weapon and weapon.allowedSlots and not contains(weapon.allowedSlots, slot) then
		return false
	end
	local offhand = EquipmentDefUtils.getOffhand(def)
	if offhand and offhand.allowedSlots and not contains(offhand.allowedSlots, slot) then
		return false
	end
	return true
end

local function checkItem(path: string, item: any, inBag: boolean, problems: { string }): any?
	local itemId = itemIdOf(item)
	if type(item) ~= "string" and type(item) ~= "table" then
		table.insert(problems, `{path}: an item is an id or a table, got {typeof(item)}`)
		return nil
	end
	if type(itemId) ~= "string" then
		table.insert(problems, `{path}: item id missing (first entry)`)
		return nil
	end
	local def = Registry.get(itemId)
	if not def then
		table.insert(problems, `{path}: unknown item '{itemId}'`)
		return nil
	end
	if type(item) == "table" then
		for key in pairs(item) do
			local known = key == 1
				or key == "rarity"
				or key == "itemLevel"
				or key == "affixes"
				or key == "meta"
				or (inBag and (key == 2 or key == "count" or key == "slot"))
			if not known then
				table.insert(problems, `{path}: unknown item field '{tostring(key)}'`)
			end
		end
		if item.rarity ~= nil and not RARITIES[item.rarity] then
			table.insert(problems, `{path}: unknown rarity '{tostring(item.rarity)}' (normal, magic, rare, unique)`)
		end
		if item.itemLevel ~= nil and (not isWhole(item.itemLevel) or item.itemLevel < 1) then
			table.insert(problems, `{path}: itemLevel must be a whole number >= 1`)
		end
		if item.meta ~= nil and type(item.meta) ~= "table" then
			table.insert(problems, `{path}: meta must be a table`)
		end
		if item.affixes ~= nil then
			if not isList(item.affixes) then
				table.insert(problems, `{path}: affixes must be a list`)
			elseif not EquipmentDefUtils.isEquipment(def) then
				table.insert(problems, `{path}: '{itemId}' is not equipment and takes no affixes`)
			else
				local level = item.itemLevel or EquipmentDefUtils.resolveInstanceItemLevel(def, item.meta)
				for index, affix in ipairs(item.affixes) do
					local affixId = if type(affix) == "table" then affix[1] else affix
					local tier = if type(affix) == "table" then affix.tier else nil
					if type(affixId) ~= "string" then
						table.insert(problems, `{path}.affixes[{index}]: affix id missing`)
					else
						local _, err = AffixRollService.rollNamed(def, level, affixId, tier)
						if err then
							table.insert(problems, `{path}.affixes[{index}]: {err}`)
						end
					end
				end
			end
		end
	end
	local count = countOf(item)
	if inBag and (not isWhole(count) or count < 1) then
		table.insert(problems, `{path}: count must be a whole number >= 1`)
	end
	return def
end

-- Branch XP for a BranchSpec, or nil with the reason.
local function branchXp(branch: string, value: any): (number?, string?)
	local cap = MasteryXP.capOf(branch)
	if type(value) == "number" then
		if value < 0 or value ~= value then
			return nil, "XP must be >= 0"
		end
		if value > cap then
			return nil, `XP {value} is over the branch's cap of {cap}`
		end
		return value, nil
	end
	if value == "mastered" then
		return cap, nil
	end
	if type(value) == "table" and isWhole(value.rank) then
		local rank = value.rank
		if branch == "trunk" then
			if rank == 0 then
				return 0, nil
			end
			local xp = MasteryXP.TRUNK_RANKS[rank]
			return xp, if xp then nil else `trunk rank {rank} does not exist (0-{#MasteryXP.TRUNK_RANKS})`
		end
		local xp = MasteryXP.BRANCH_RANKS[rank]
		return xp, if xp then nil else `branch rank {rank} does not exist (1-{#MasteryXP.BRANCH_RANKS})`
	end
	return nil, `expected XP, "mastered" or \{ rank = n }, got {typeof(value)}`
end

local function resolveXp(spec: Spec): number
	if type(spec.level) == "number" then
		return CharacterXP.totalFor(spec.level)
	end
	return if type(spec.xp) == "number" then spec.xp else 0
end

-- Track -> branch -> XP, for the tracks the spec names. Problems go into `problems` when given.
local function resolveMasteries(spec: Spec, problems: { string }?): { [string]: { [string]: number } }
	local out: { [string]: { [string]: number } } = {}
	local mastery = spec.mastery
	if mastery == nil then
		return out
	end
	if type(mastery) ~= "table" then
		if problems then
			table.insert(problems, "mastery must be a map of track -> branch -> XP")
		end
		return out
	end
	for trackId, branches in pairs(mastery :: any) do
		if type(trackId) ~= "string" or not MasteryTracks.get(trackId) then
			if problems then
				table.insert(problems, `mastery: unknown track '{tostring(trackId)}'`)
			end
			continue
		end
		if type(branches) ~= "table" then
			if problems then
				table.insert(problems, `mastery.{trackId}: expected a map of branch -> XP`)
			end
			continue
		end
		local resolved: { [string]: number } = {}
		for branch, value in pairs(branches) do
			if not table.find(BRANCHES, branch) then
				if problems then
					table.insert(problems, `mastery.{trackId}: unknown branch '{tostring(branch)}' (trunk, a, b)`)
				end
				continue
			end
			local xp, err = branchXp(branch, value)
			if xp then
				resolved[branch] = xp
			elseif problems then
				table.insert(problems, `mastery.{trackId}.{branch}: {err}`)
			end
		end
		-- A branch reached by rank only counts once the trunk opens the branches.
		for _, branch in ipairs({ "a", "b" }) do
			local value = branches[branch]
			if
				problems
				and type(value) == "table"
				and resolved[branch] ~= nil
				and (resolved.trunk or 0) < MasteryXP.BRANCH_ENTRY
			then
				table.insert(
					problems,
					`mastery.{trackId}.{branch}: a branch rank needs trunk XP >= {MasteryXP.BRANCH_ENTRY}`
				)
			end
		end
		out[trackId] = resolved
	end
	return out
end

local function checkNameList(path: string, value: any, isKnown: (string) -> boolean, what: string, problems: { string })
	if value == nil then
		return
	end
	if not isList(value) then
		table.insert(problems, `{path} must be a list`)
		return
	end
	local seen: { [string]: boolean } = {}
	for index, name in ipairs(value) do
		if type(name) ~= "string" or not isKnown(name) then
			table.insert(problems, `{path}[{index}]: unknown {what} '{tostring(name)}'`)
		elseif seen[name] then
			table.insert(problems, `{path}[{index}]: '{name}' listed twice`)
		end
		if type(name) == "string" then
			seen[name] = true
		end
	end
end

-- Every problem with the spec (already resolved), or an empty list.
function Specs.validate(spec: Spec): { string }
	local problems: { string } = {}
	local raw = spec :: any

	for key in pairs(raw) do
		if type(key) ~= "string" or not FIELDS[key] then
			table.insert(problems, `unknown field '{tostring(key)}'`)
		end
	end

	-- Level.
	if raw.level ~= nil and raw.xp ~= nil then
		table.insert(problems, "give level or xp, not both")
	end
	if raw.level ~= nil and (not isWhole(raw.level) or raw.level < 1 or raw.level > CharacterXP.MAX_LEVEL) then
		table.insert(problems, `level must be a whole number from 1 to {CharacterXP.MAX_LEVEL}`)
	end
	if raw.xp ~= nil and (type(raw.xp) ~= "number" or raw.xp < 0) then
		table.insert(problems, "xp must be a number >= 0")
	end
	local level = CharacterXP.levelOf(resolveXp(spec))

	-- Attributes.
	if raw.attributes ~= nil then
		if type(raw.attributes) ~= "table" then
			table.insert(problems, "attributes must be a map")
		else
			for name, value in pairs(raw.attributes) do
				if name ~= "unspent" and not table.find(AttributeTypes.AllAttributeNames, name) then
					table.insert(
						problems,
						`attributes: unknown attribute '{tostring(name)}' ({table.concat(AttributeTypes.AllAttributeNames, ", ")}, unspent)`
					)
				elseif not isWhole(value) or value < 0 then
					table.insert(problems, `attributes.{name}: must be a whole number >= 0`)
				elseif name ~= "unspent" and value > AttributesConfig.MAX_ATTRIBUTE_VALUE then
					table.insert(problems, `attributes.{name}: at most {AttributesConfig.MAX_ATTRIBUTE_VALUE}`)
				end
			end
		end
	end

	-- Mastery and what it unlocks.
	local masteries = resolveMasteries(spec, problems)
	checkNameList("attuned", raw.attuned, function(name)
		return MasteryTracks.get(name) ~= nil
	end, "track", problems)
	local attuned: { string } = if isList(raw.attuned) then raw.attuned else {}
	if #attuned > Attunement.slotsFor(level) then
		table.insert(problems, `attuned: level {level} has {Attunement.slotsFor(level)} attunement slot(s), {#attuned} given`)
	end
	local everyTrack: { [string]: { [string]: number } } = {}
	for _, track in ipairs(MasteryTracks.list()) do
		everyTrack[track.id] = masteries[track.id] or {}
	end

	-- Skills and bar.
	checkNameList("skills", raw.skills, function(name)
		return SkillsConfig.skills[name] ~= nil
	end, "skill", problems)
	-- A slot may hold a skill the character does not own, as a real save's can (gear that granted
	-- it came off): it stays there, uncastable. Only names that are not skills at all are wrong.
	if raw.bar ~= nil then
		if not isList(raw.bar) then
			table.insert(problems, "bar must be a list of slot sets")
		else
			if #raw.bar > LoadoutTypes.MAX_SETS then
				table.insert(problems, `bar: at most {LoadoutTypes.MAX_SETS} slot sets`)
			end
			for setIndex, set in ipairs(raw.bar) do
				if not isList(set) then
					table.insert(problems, `bar[{setIndex}] must be a list of skill names`)
					continue
				end
				if #set > LoadoutTypes.SLOTS_PER_SET then
					table.insert(problems, `bar[{setIndex}]: at most {LoadoutTypes.SLOTS_PER_SET} slots`)
				end
				for slot, skill in ipairs(set) do
					if skill == LoadoutTypes.EMPTY then
						continue
					end
					if type(skill) ~= "string" or SkillsConfig.skills[skill] == nil then
						table.insert(problems, `bar[{setIndex}][{slot}]: unknown skill '{tostring(skill)}'`)
					end
				end
			end
		end
	end
	if raw.activeSet ~= nil and (not isWhole(raw.activeSet) or raw.activeSet < 1 or raw.activeSet > LoadoutTypes.MAX_SETS) then
		table.insert(problems, `activeSet must be a whole number from 1 to {LoadoutTypes.MAX_SETS}`)
	end

	-- Equipment.
	local mainDef: any = nil
	if raw.equipment ~= nil then
		if type(raw.equipment) ~= "table" then
			table.insert(problems, "equipment must be a map of equip slot -> item")
		else
			local defs: { [string]: any } = {}
			for slot, item in pairs(raw.equipment) do
				local path = `equipment.{tostring(slot)}`
				if type(slot) ~= "string" or not ItemEnums.isEquipSlot(slot) then
					local names = {}
					for _, name in pairs(ItemEnums.EquipSlot) do
						table.insert(names, name)
					end
					table.sort(names)
					table.insert(problems, `{path}: unknown equip slot ({table.concat(names, ", ")})`)
					continue
				end
				local def = checkItem(path, item, false, problems)
				if not def then
					continue
				end
				if not EquipmentDefUtils.isEquipment(def) then
					table.insert(problems, `{path}: '{def.id}' is not equipment`)
				elseif not slotAllowed(def, slot) then
					table.insert(problems, `{path}: '{def.id}' cannot be equipped in {slot}`)
				else
					defs[slot] = def
				end
			end
			mainDef = defs.Main
			local mainWeapon = mainDef and EquipmentDefUtils.getWeapon(mainDef)
			if mainWeapon and mainWeapon.handedness == "two_handed" and raw.equipment.Secondary then
				table.insert(problems, `equipment: '{mainDef.id}' is two-handed, so Secondary must be empty`)
			end
		end
	end

	-- Bag.
	local capacity = if raw.capacity ~= nil then raw.capacity else DEFAULT_CAPACITY
	if raw.capacity ~= nil and (not isWhole(raw.capacity) or raw.capacity < 1 or raw.capacity > MAX_CAPACITY) then
		table.insert(problems, `capacity must be a whole number from 1 to {MAX_CAPACITY}`)
	end
	if raw.bag ~= nil then
		if not isList(raw.bag) then
			table.insert(problems, "bag must be a list of items")
		else
			local needed = 0
			local placed: { [number]: boolean } = {}
			for index, item in ipairs(raw.bag) do
				local path = `bag[{index}]`
				local def = checkItem(path, item, true, problems)
				local count = countOf(item)
				if def and isWhole(count) then
					local stacks = math.ceil(count / stackLimitOf(def))
					local slot = if type(item) == "table" then item.slot else nil
					if slot ~= nil then
						if not isWhole(slot) or slot < 1 or slot > capacity then
							table.insert(problems, `{path}: slot must be a whole number from 1 to {capacity}`)
						elseif stacks > 1 then
							table.insert(problems, `{path}: {count} is more than one stack, so it cannot take a single slot`)
						elseif placed[slot] then
							table.insert(problems, `{path}: slot {slot} is already taken`)
						else
							placed[slot] = true
						end
					end
					needed += stacks
				end
			end
			if needed > capacity then
				table.insert(problems, `bag: needs {needed} slots, capacity is {capacity}`)
			end
		end
	end

	-- Forms.
	if raw.shapes ~= nil then
		if type(raw.shapes) ~= "table" then
			table.insert(problems, "shapes must be a map of weapon class key -> profile id")
		else
			local mainWeapon = mainDef and EquipmentDefUtils.getWeapon(mainDef)
			for classKey, shapeId in pairs(raw.shapes) do
				local path = `shapes.{tostring(classKey)}`
				local shape = if type(shapeId) == "string" then BasicAttackProfileRegistry.get(shapeId) else nil
				if type(classKey) ~= "string" or #BasicAttackProfileRegistry.shapesFor(classKey) == 0 then
					table.insert(problems, `{path}: unknown weapon class key`)
				elseif not shape then
					table.insert(problems, `{path}: unknown basic attack profile '{tostring(shapeId)}'`)
				elseif not BasicAttackProfileRegistry.fitsClass(shape, classKey) then
					table.insert(problems, `{path}: '{shapeId}' is not a shape for {classKey}`)
				elseif
					not MasteryTree.isShapeUnlocked(shapeId, everyTrack, attuned)
					and not (mainWeapon and contains(mainWeapon.grantsShapes, shapeId))
				then
					local node, tree = MasteryTrees.nodeForShape(shapeId)
					local why = if node and tree
						then `needs node '{node.id}' unlocked and in effect (attack-type tracks must be attuned beyond their root)`
						else "no mastery node unlocks it and the main hand does not grant it"
					table.insert(problems, `{path}: '{shapeId}' is locked: {why}`)
				end
			end
		end
	end
	if raw.infusion ~= nil and raw.infusion ~= "" then
		local node = if type(raw.infusion) == "string" then MasteryTrees.node(raw.infusion) else nil
		if not node or node.kind ~= "infusion" then
			table.insert(problems, `infusion: unknown infusion node '{tostring(raw.infusion)}'`)
		elseif not MasteryTree.isInfusionUnlocked(node.id, everyTrack, attuned) then
			table.insert(problems, `infusion: '{node.id}' is locked by the mastery given`)
		end
	end

	-- Passives.
	checkNameList("passives", raw.passives, function(name)
		local node = MasteryTrees.node(name)
		return node ~= nil and node.kind == "select"
	end, "selectable passive", problems)
	if isList(raw.passives) then
		local slots = PassivePool.slotsFor(level)
		if #raw.passives > slots then
			table.insert(problems, `passives: level {level} has {slots} passive slot(s), {#raw.passives} given`)
		end
		for index, nodeId in ipairs(raw.passives) do
			local node, tree = MasteryTrees.node(nodeId)
			if node and tree and node.kind == "select" then
				local isAttuned = table.find(attuned, tree.track) ~= nil
				local branches = everyTrack[tree.track] or {}
				if not MasteryTree.isUnlocked(node, branches, isAttuned) then
					table.insert(problems, `passives[{index}]: '{nodeId}' is locked by the mastery given`)
				elseif not MasteryTree.isActive(node, tree.track, isAttuned) then
					table.insert(problems, `passives[{index}]: '{nodeId}' needs {tree.track} attuned`)
				end
			end
		end
	end

	-- Pools and stats.
	if raw.pools ~= nil then
		if type(raw.pools) ~= "table" then
			table.insert(problems, "pools must be a map of pool -> value")
		else
			for pool, value in pairs(raw.pools) do
				if not POOLS[pool] then
					table.insert(problems, `pools: unknown pool '{tostring(pool)}'`)
				elseif type(value) ~= "number" or value < 0 then
					table.insert(problems, `pools.{pool}: must be a number >= 0`)
				end
			end
		end
	end
	if raw.stats ~= nil then
		if type(raw.stats) ~= "table" then
			table.insert(problems, "stats must be a map of stat -> base value")
		else
			local defaults = StatsConfig.createDefaultStats() :: any
			for stat, value in pairs(raw.stats) do
				if type(stat) ~= "string" or defaults[stat] == nil then
					table.insert(problems, `stats: unknown stat '{tostring(stat)}'`)
				elseif type(value) ~= "number" then
					table.insert(problems, `stats.{stat}: must be a number`)
				end
			end
		end
	end

	return problems
end

-- The instance meta to create an item with: `meta` as given, with the shorthands laid over it.
local function metaFor(def: any, item: any): { [string]: any }?
	if type(item) ~= "table" then
		return nil
	end
	local meta: { [string]: any } = Specs.deepCopy(item.meta) or {}
	if item.rarity then
		meta.rarity = item.rarity
	end
	if item.itemLevel then
		meta.itemLevel = item.itemLevel
	end
	if item.affixes then
		local level = EquipmentDefUtils.resolveInstanceItemLevel(def, meta)
		local affixes = {}
		for _, affix in ipairs(item.affixes) do
			local affixId = if type(affix) == "table" then affix[1] else affix
			local tier = if type(affix) == "table" then affix.tier else nil
			local rolled = AffixRollService.rollNamed(def, level, affixId, tier)
			if rolled then
				table.insert(affixes, rolled)
			end
		end
		meta.affixes = affixes
	end
	return if next(meta) ~= nil then meta else nil
end

-- Items made through the inventory's own creation path (rolls, charges, display names), then taken
-- back out of the live registry: the save is what restores them, under the same uids.
local function makeStacks(item: any, items: { [string]: any }): { string }
	local itemId = itemIdOf(item)
	local def = Registry.get(itemId) :: any
	local meta = metaFor(def, item)
	local remaining = countOf(item)
	local uids: { string } = {}
	while remaining > 0 do
		local size = math.min(remaining, stackLimitOf(def))
		local inst = ItemInstances.create(itemId, size, meta)
		if not inst then
			break
		end
		ItemInstances.remove(inst.uid)
		items[inst.uid] = {
			itemId = inst.itemId,
			stackSize = inst.stackSize,
			meta = if inst.meta then PlayerDataSchema.saveable(Specs.deepCopy(inst.meta), `items.{inst.uid}.meta`) else nil,
		}
		table.insert(uids, inst.uid)
		remaining -= size
	end
	return uids
end

local function buildInventory(spec: Spec): PlayerDataSchema.SavedInventory
	local capacity = spec.capacity or DEFAULT_CAPACITY
	local items: { [string]: any } = {}
	local equipment: { [string]: string } = {}
	for slot, item in pairs(spec.equipment or {}) do
		if item then
			local uids = makeStacks(item, items)
			if uids[1] then
				equipment[slot] = uids[1]
			end
		end
	end

	local slots: { string } = table.create(capacity, "")
	local loose: { string } = {}
	for _, item in ipairs(spec.bag or {}) do
		local uids = makeStacks(item, items)
		local slot = if type(item) == "table" then item.slot else nil
		if slot and uids[1] then
			slots[slot] = uids[1]
		else
			for _, uid in ipairs(uids) do
				table.insert(loose, uid)
			end
		end
	end
	local nextLoose = 1
	for slot = 1, capacity do
		if slots[slot] == "" and loose[nextLoose] then
			slots[slot] = loose[nextLoose]
			nextLoose += 1
		end
	end

	return {
		capacity = capacity,
		slots = slots,
		equipment = equipment,
		items = items,
	}
end

-- The save a (valid, resolved) spec describes, on a brand-new save's template. Shares no tables
-- with the spec, so a preset is never changed by what happens to the save in play.
function Specs.buildSave(spec: Spec): PlayerSaveData
	local data = PlayerDataSchema.template()
	-- The starting kit is the dev session's business; a built save never asks for it.
	data.starterKitGranted = true
	data.character.xp = resolveXp(spec)

	if spec.attributes then
		local base: { [string]: number } = {}
		for name, value in pairs(spec.attributes) do
			if name ~= "unspent" then
				base[name] = value
			end
		end
		data.attributes = {
			base = base,
			availablePoints = spec.attributes.unspent,
		}
	end

	for trackId, branches in pairs(resolveMasteries(spec, nil)) do
		data.progression.masteries[trackId] = { branches = branches }
	end
	data.progression.attunement = Specs.deepCopy(spec.attuned or {})
	data.progression.shapes = Specs.deepCopy(spec.shapes or {})
	data.progression.infusion = spec.infusion or ""
	data.progression.passives = Specs.deepCopy(spec.passives or {})

	if spec.bar then
		local sets = {}
		for index = 1, LoadoutTypes.MAX_SETS do
			local given = spec.bar[index] or {}
			local slots = {}
			for slot = 1, LoadoutTypes.SLOTS_PER_SET do
				slots[slot] = given[slot] or LoadoutTypes.EMPTY
			end
			sets[index] = { slots = slots }
		end
		data.loadout = { activeSet = spec.activeSet or 1, sets = sets }
	elseif spec.activeSet then
		data.loadout.activeSet = spec.activeSet
	end

	data.inventory = buildInventory(spec)
	return Specs.deepCopy(data)
end

return Specs
