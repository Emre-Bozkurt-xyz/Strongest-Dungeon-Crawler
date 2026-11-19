--!strict
-- What a character editor may offer: every valid choice and limit a spec field takes, read from the
-- game's own content (attributes, the XP curves, the mastery trees, skills, items and their affixes,
-- basic attack shapes, stats), so the editor's pickers can never offer something the validator would
-- refuse. Built once per server (content does not change at run time) and returned as JSON-safe data.
--
-- Also the unlock rule of a mastery node turned around: the least branch XP that opens it
-- (`requirement`), which the editor's node search and `character unlock` both use.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local AttributeTypes = require(ReplicatedStorage.Shared.AttributeTypes)
local StatTypes = require(ReplicatedStorage.Shared.StatTypes)
local CharacterXP = require(ReplicatedStorage.Shared.progression.CharacterXP)
local MasteryXP = require(ReplicatedStorage.Shared.progression.MasteryXP)
local MasteryTracks = require(ReplicatedStorage.Shared.progression.MasteryTracks)
local MasteryTrees = require(ReplicatedStorage.Shared.progression.MasteryTrees)
local Attunement = require(ReplicatedStorage.Shared.progression.Attunement)
local PassivePool = require(ReplicatedStorage.Shared.progression.PassivePool)
local LoadoutTypes = require(ReplicatedStorage.Shared.skills.LoadoutTypes)
local BasicAttackProfileRegistry = require(ReplicatedStorage.Shared.skills.BasicAttackProfileRegistry)
local BasicAttackProfileTypes = require(ReplicatedStorage.Shared.skills.BasicAttackProfileTypes)
local Registry = require(ReplicatedStorage.Shared.items.Registry)
local ItemEnums = require(ReplicatedStorage.Shared.items.ItemEnums)
local EquipmentDefUtils = require(ReplicatedStorage.Shared.items.EquipmentDefUtils)
local AffixRegistry = require(ReplicatedStorage.Shared.items.AffixRegistry)

local Server = ServerScriptService.Server
local PlayerDataSchema = require(Server.PlayerData.PlayerDataSchema)
local SkillsConfig = require(Server.SkillsFramework.SkillsConfig)
local StatsConfig = require(Server.Stats.Config.StatsConfig)
local AttributesConfig = require(Server.Stats.Config.AttributesConfig)
local Specs = require(script.Parent.Specs)

local Schema = {}

-- The order a character sheet reads in, rather than alphabetical.
local POOL_ORDER = { "Health", "Mana", "Stamina", "ManaShield" }
local SLOT_ORDER = { "Main", "Secondary", "Head", "Neck", "Body", "Hands", "Waist", "Feet", "Ring1", "Ring2" }
local RARITIES = { "normal", "magic", "rare", "unique" }

local function ordered(preferred: { string }, all: { string }): { string }
	local out: { string } = {}
	for _, name in ipairs(preferred) do
		if table.find(all, name) then
			table.insert(out, name)
		end
	end
	local rest: { string } = {}
	for _, name in ipairs(all) do
		if not table.find(out, name) then
			table.insert(rest, name)
		end
	end
	table.sort(rest)
	for _, name in ipairs(rest) do
		table.insert(out, name)
	end
	return out
end

export type Requirement = { trunk: number?, a: number?, b: number? }

-- The least XP per branch that opens `node` (a branch not named needs none), whether it also needs
-- its track attuned to be open (end nodes) or in effect (attack-type nodes past the root), and the
-- requirement in words, by XP and by rank.
function Schema.requirement(node: any, trackId: string): (Requirement, boolean, string, string)
	local rank = node.rank or 0
	local track = MasteryTracks.get(trackId)
	local attackType = track ~= nil and track.family == "attack"
	local needsAttunement = node.branch == "end" or (attackType and not (node.branch == "trunk" and rank == 0))
	local join = MasteryXP.BRANCH_RANKS[MasteryXP.JOIN_RANK]
	if node.branch == "trunk" then
		if rank == 0 then
			return {}, needsAttunement, "open from the start", "open from the start"
		end
		local xp = MasteryXP.TRUNK_RANKS[rank]
		return { trunk = xp }, needsAttunement, `trunk → {xp}`, `trunk → rank {rank}`
	elseif node.branch == "a" or node.branch == "b" then
		if rank == 1 then
			return { trunk = MasteryXP.BRANCH_ENTRY },
				needsAttunement,
				`trunk → {MasteryXP.BRANCH_ENTRY}`,
				`{node.branch} → rank 1`
		end
		local xp = MasteryXP.BRANCH_RANKS[rank]
		return { trunk = MasteryXP.BRANCH_ENTRY, [node.branch] = xp } :: any,
			needsAttunement,
			`{node.branch} → {xp}`,
			`{node.branch} → rank {rank}`
	end
	local suffix = if node.branch == "end" then " + attuned" else ""
	return { trunk = MasteryXP.BRANCH_ENTRY, a = join, b = join },
		needsAttunement,
		`a, b → {join}{suffix}`,
		`a, b → rank {MasteryXP.JOIN_RANK}{suffix}`
end

-- A node by id, or by display name ignoring case.
function Schema.findNode(ref: string): (any?, any?)
	local node, tree = MasteryTrees.node(ref)
	if node then
		return node, tree
	end
	local wanted = string.lower(ref)
	for _, track in ipairs(MasteryTracks.list()) do
		local candidate = MasteryTrees.get(track.id)
		for _, each in ipairs(candidate and candidate.nodes or {}) do
			if string.lower(each.displayName) == wanted then
				return each, candidate
			end
		end
	end
	return nil, nil
end

-- Weapon class keys that have at least one selectable shape, "unarmed" first.
function Schema.classKeys(): { string }
	local keys: { string } = {}
	local candidates = { BasicAttackProfileTypes.UNARMED_CLASS_KEY }
	for _, class in ipairs(ItemEnums.listWeaponClasses()) do
		table.insert(candidates, class)
	end
	for _, key in ipairs(candidates) do
		if #BasicAttackProfileRegistry.shapesFor(key) > 0 and not table.find(keys, key) then
			table.insert(keys, key)
		end
	end
	return keys
end

local function itemEntry(def: any): any
	local isEquipment = EquipmentDefUtils.isEquipment(def)
	local slots: { string } = {}
	if isEquipment then
		for _, slot in ipairs(SLOT_ORDER) do
			if Specs.slotAllowed(def, slot) then
				table.insert(slots, slot)
			end
		end
	end
	local weapon = EquipmentDefUtils.getWeapon(def)
	local affixes = {}
	if isEquipment then
		local context = AffixRegistry.getContext(def)
		for _, affix in ipairs(AffixRegistry.list()) do
			local tiers: { number } = {}
			local minLevels: { number } = {}
			for _, tier in ipairs(affix.tiers) do
				if AffixRegistry.tierAppliesToContext(tier, context) then
					table.insert(tiers, tier.tier)
					table.insert(minLevels, tier.minItemLevel)
				end
			end
			if #tiers > 0 then
				table.insert(affixes, { id = affix.id, kind = affix.kind, tiers = tiers, minLevels = minLevels })
			end
		end
	end
	return {
		id = def.id,
		name = def.name,
		equipment = isEquipment,
		slots = slots,
		weaponClass = if weapon then weapon.class else nil,
		twoHanded = if weapon then weapon.handedness == "two_handed" else nil,
		stackLimit = if def.stackLimit and def.stackLimit > 0 then def.stackLimit else 1,
		rarities = if def.rarity then { def.rarity } elseif isEquipment then RARITIES else {},
		baseItemLevel = if isEquipment then EquipmentDefUtils.getBaseItemLevel(def) else nil,
		affixes = affixes,
	}
end

local cached: any = nil

function Schema.build(): any
	if cached then
		return cached
	end

	local levelTotals: { number } = {}
	for level = 1, CharacterXP.MAX_LEVEL do
		levelTotals[level] = CharacterXP.totalFor(level)
	end
	local masteryTotals: { number } = {}
	for level = 1, MasteryXP.MAX_LEVEL do
		masteryTotals[level] = MasteryXP.totalFor(level)
	end

	local tracks = {}
	local nodes = {}
	local infusions = {}
	local passives = {}
	for _, track in ipairs(MasteryTracks.list()) do
		local tree = MasteryTrees.get(track.id)
		table.insert(tracks, {
			id = track.id,
			name = track.displayName,
			family = track.family,
			branches = if tree then { a = tree.branches.a, b = tree.branches.b } else { a = "a", b = "b" },
		})
		for _, node in ipairs(tree and tree.nodes or {}) do
			local requirement, needsAttunement, byXp, byRank = Schema.requirement(node, track.id)
			table.insert(nodes, {
				id = node.id,
				name = node.displayName,
				kind = node.kind,
				track = track.id,
				branch = node.branch,
				rank = node.rank,
				requirement = requirement,
				unlockXp = byXp,
				unlockRank = byRank,
				needsAttunement = needsAttunement,
				needsPassiveSlot = node.kind == "select",
				built = node.kind ~= "form" or (node.shapes ~= nil and #node.shapes > 0),
			})
			if node.kind == "infusion" then
				table.insert(infusions, { id = node.id, name = node.displayName, track = track.id })
			elseif node.kind == "select" then
				table.insert(passives, { id = node.id, name = node.displayName, track = track.id })
			end
		end
	end

	local skills = {}
	local skillNames: { string } = {}
	for name in pairs(SkillsConfig.skills) do
		table.insert(skillNames, name)
	end
	table.sort(skillNames)
	for _, name in ipairs(skillNames) do
		local data = SkillsConfig.skills[name] :: any
		table.insert(skills, { id = name, name = if type(data.name) == "string" then data.name else name })
	end

	local slotNames: { string } = {}
	for _, slot in pairs(ItemEnums.EquipSlot) do
		table.insert(slotNames, slot)
	end

	local items = {}
	for _, def in ipairs(Registry.list()) do
		table.insert(items, itemEntry(def))
	end
	table.sort(items, function(a, b)
		return a.id < b.id
	end)

	local shapes: { [string]: any } = {}
	local classKeys = Schema.classKeys()
	for _, key in ipairs(classKeys) do
		local list = {}
		for _, profile in ipairs(BasicAttackProfileRegistry.shapesFor(key)) do
			table.insert(list, { id = profile.id, name = profile.displayName })
		end
		shapes[key] = list
	end

	-- The file's defaults: the schema is built once per server, so a default retuned this session is
	-- read from the state's `statDefaults` instead.
	local stats = {}
	for _, name in ipairs(StatsConfig.names()) do
		table.insert(stats, { name = name, default = StatsConfig.fileDefault(name) })
	end

	local poolNames: { string } = {}
	for _, pool in pairs(StatTypes.PoolStats) do
		table.insert(poolNames, pool)
	end

	cached = {
		attributes = {
			names = table.clone(AttributeTypes.AllAttributeNames),
			min = AttributesConfig.MIN_ATTRIBUTE_VALUE,
			max = AttributesConfig.MAX_ATTRIBUTE_VALUE,
			defaultUnspent = AttributesConfig.DefaultAttributePoints,
		},
		pools = ordered(POOL_ORDER, poolNames),
		level = { max = CharacterXP.MAX_LEVEL, totals = levelTotals, pointsPerLevel = CharacterXP.POINTS_PER_LEVEL },
		mastery = {
			trunkCap = MasteryXP.TRUNK_CAP,
			branchCap = MasteryXP.BRANCH_CAP,
			trunkRanks = table.clone(MasteryXP.TRUNK_RANKS),
			branchRanks = table.clone(MasteryXP.BRANCH_RANKS),
			branchEntry = MasteryXP.BRANCH_ENTRY,
			joinRank = MasteryXP.JOIN_RANK,
			maxLevel = MasteryXP.MAX_LEVEL,
			levelTotals = masteryTotals,
			tracks = tracks,
			nodes = nodes,
		},
		attunementSlotLevels = table.clone(Attunement.SLOT_LEVELS),
		passiveSlotLevels = table.clone(PassivePool.SLOT_LEVELS),
		skills = skills,
		bar = { sets = LoadoutTypes.MAX_SETS, slots = LoadoutTypes.SLOTS_PER_SET },
		equipSlots = ordered(SLOT_ORDER, slotNames),
		items = items,
		rarities = RARITIES,
		classKeys = classKeys,
		shapes = shapes,
		infusions = infusions,
		passives = passives,
		stats = stats,
		capacity = { default = PlayerDataSchema.template().inventory.capacity, max = Specs.MAX_CAPACITY },
	}
	return cached
end

return Schema
