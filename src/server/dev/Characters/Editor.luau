--!strict
-- The character editor's server half: patches laid over the live build, the fields that can change
-- on a live player without rebuilding them, which fields an edit touched, and the read-outs an
-- editor shows. Characters owns the sessions and the rebuilds; this is what it computes them with.
--
-- A patch is a partial spec, merged by the spec rules (Types): maps merge key by key, lists and
-- items replace, `false` removes. Two additions, for the editor:
--   - `level` and `xp` replace each other, so a patch naming one drops the other from the build;
--   - a bag entry `{ keep = i, count = n? }` stands for the i-th item of the build's bag (as the
--     state read-out lists it), so a bag edit need not send every item's exact meta back.
--
-- Fields with a direct path in the game (`CHEAP`) are set on the live player; anything else is
-- applied by rebuilding the player from the merged spec, which also clears cooldowns, statuses and
-- the skill in progress.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local AttributeTypes = require(ReplicatedStorage.Shared.AttributeTypes)
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
local EquipmentDefUtils = require(ReplicatedStorage.Shared.items.EquipmentDefUtils)

local Server = ServerScriptService.Server
local PlayerDataService = require(Server.PlayerData.PlayerDataService)
local StatsManager = require(Server.Stats.StatsManager)
local AttributesManager = require(Server.Stats.AttributesManager)
local AttributesConfig = require(Server.Stats.Config.AttributesConfig)
local InventoryService = require(Server.Inventory.InventoryService)

local Specs = require(script.Parent.Specs)
local Schema = require(script.Parent.Schema)
local Holds = require(script.Parent.Holds)
local Types = require(script.Parent.Types)

type Spec = Types.Spec

local Editor = {}

local CHEAP: { [string]: boolean } = {
	level = true,
	xp = true,
	attributes = true,
	mastery = true,
	attuned = true,
	pools = true,
}

-- Fields whose edits are tracked per key ("attributes.Strength") rather than whole.
local KEYED: { [string]: boolean } = {
	attributes = true,
	mastery = true,
	equipment = true,
	pools = true,
	stats = true,
	shapes = true,
}

local BRANCHES = { "trunk", "a", "b" }

-- Lazily, so requiring Characters never decides the order game services start in.
local function progression(name: string): any
	return require((Server :: any).Progression[name])
end

local function deepEqual(a: any, b: any): boolean
	if type(a) ~= "table" or type(b) ~= "table" then
		return a == b
	end
	for key, value in pairs(a) do
		if not deepEqual(value, b[key]) then
			return false
		end
	end
	for key in pairs(b) do
		if a[key] == nil then
			return false
		end
	end
	return true
end

-- `patch` with its bag `keep` entries replaced by the items they stand for in `current`. Nil and the
-- reason when one names no item.
function Editor.expand(patch: { [string]: any }, current: Spec): ({ [string]: any }?, string?)
	local out = Specs.deepCopy(patch)
	if type(out.bag) == "table" then
		local bag = {}
		local currentBag = (current :: any).bag or {}
		for index, entry in ipairs(out.bag) do
			if type(entry) == "table" and entry.keep ~= nil then
				local kept = currentBag[entry.keep]
				if kept == nil then
					return nil, `bag[{index}]: keep {tostring(entry.keep)} names no item in the bag`
				end
				local item = Specs.deepCopy(kept)
				if entry.count ~= nil then
					if type(item) ~= "table" then
						item = { item }
					end
					item.count = nil
					item[2] = entry.count
				end
				table.insert(bag, item)
			else
				table.insert(bag, entry)
			end
		end
		out.bag = bag
	end
	return out, nil
end

-- The build with `patch` laid over it.
function Editor.merge(current: Spec, patch: { [string]: any }): Spec
	local merged = Specs.merge(current :: any, patch)
	if patch.level ~= nil then
		merged.xp = nil
	end
	if patch.xp ~= nil then
		merged.level = nil
	end
	return merged :: Spec
end

-- Whether every field in `patch` can be set on the live player without a rebuild.
function Editor.isCheap(patch: { [string]: any }): boolean
	for key in pairs(patch) do
		if not CHEAP[key] then
			return false
		end
	end
	return true
end

-- Sets the cheap fields of `patch` (see isCheap) on the player. `merged` is the build after it.
-- Level first, since attunement slots hang off it.
function Editor.applyInPlace(player: Player, patch: { [string]: any }, merged: Spec)
	if patch.level ~= nil or patch.xp ~= nil then
		progression("CharacterService").setXp(player, Specs.resolveXp(merged))
	end
	if type(patch.mastery) == "table" then
		local masteries = progression("MasteryService")
		for trackId, branches in pairs(patch.mastery) do
			for _, branch in ipairs(BRANCHES) do
				local value = if type(branches) == "table" then branches[branch] else false
				if value ~= nil then
					local xp = if value == false then 0 else Specs.branchXp(branch, value)
					if xp then
						masteries.setBranchXp(player, trackId, branch, xp)
					end
				end
			end
		end
	end
	if patch.attuned ~= nil then
		progression("AttunementService").assign(player, (merged :: any).attuned or {})
	end
	if type(patch.attributes) == "table" then
		for name, value in pairs(patch.attributes) do
			if name == "unspent" then
				AttributesManager.setAvailableAttributePoints(
					player,
					if value == false then AttributesConfig.DefaultAttributePoints else value
				)
			else
				AttributesManager.setAttribute(player, name :: any, if value == false then 0 else value)
			end
		end
	end
	if type(patch.pools) == "table" then
		for pool, value in pairs(patch.pools) do
			Holds.setPool(player, pool, if value == false then 1 else value)
		end
	end
end

-- The paths an edit of `patch` touches: "level", "bag", "attributes.Strength", "mastery.Fire"...
function Editor.pathsOf(patch: { [string]: any }, before: Spec, after: Spec): { string }
	local paths: { string } = {}
	for field, value in pairs(patch) do
		if field == "xp" or field == "level" then
			if not table.find(paths, "level") then
				table.insert(paths, "level")
			end
		elseif KEYED[field] then
			local keys: { [string]: boolean } = {}
			if type(value) == "table" and next(value) ~= nil then
				for key in pairs(value) do
					keys[key] = true
				end
			else
				for key in pairs((before :: any)[field] or {}) do
					keys[key] = true
				end
				for key in pairs((after :: any)[field] or {}) do
					keys[key] = true
				end
			end
			for key in pairs(keys) do
				table.insert(paths, `{field}.{key}`)
			end
		else
			table.insert(paths, field)
		end
	end
	return paths
end

-- Whether `path` holds something different in `now` than in `base`.
function Editor.differs(path: string, now: Spec, base: Spec): boolean
	if path == "level" then
		return Specs.resolveXp(now) ~= Specs.resolveXp(base)
	end
	local field, key = string.match(path, "^([^%.]+)%.(.+)$")
	if field and key then
		local a = ((now :: any)[field] or {})[key]
		local b = ((base :: any)[field] or {})[key]
		return not deepEqual(a, b)
	end
	return not deepEqual((now :: any)[path], (base :: any)[path])
end

export type Problem = { field: string, message: string }

-- Validator problems keyed by the spec path they are about ("mastery.Fire.trunk", "passives[1]",
-- "level"), so an editor can show each beside its control. "" when a problem names no field.
function Editor.keyProblems(problems: { string }): { Problem }
	local out: { Problem } = {}
	for _, message in ipairs(problems) do
		local field = string.match(message, "^([%w_%.%[%]]+):")
		if not field then
			local word = string.match(message, "^(%w+) ")
			if word == "give" or word == "xp" or word == "level" then
				field = "level"
			elseif word == "capacity" or word == "activeSet" or word == "bar" or word == "skills" then
				field = word
			end
		end
		table.insert(out, { field = field or "", message = message })
	end
	return out
end

-- A list of edited paths in words, in a stable order: "Strength, Fire mastery, Main hand, bag".
function Editor.describe(paths: { string }): string
	local words: { string } = {}
	local sorted = table.clone(paths)
	table.sort(sorted)
	for _, path in ipairs(sorted) do
		local field, key = string.match(path, "^([^%.]+)%.(.+)$")
		local word: string
		if field == "attributes" then
			word = if key == "unspent" then "unspent points" else key :: string
		elseif field == "mastery" then
			word = `{key} mastery`
		elseif field == "equipment" then
			word = `{key} slot`
		elseif field == "pools" or field == "stats" then
			word = key :: string
		elseif field == "shapes" then
			word = `{key} shape`
		elseif path == "attuned" then
			word = "attunement"
		elseif path == "activeSet" then
			word = "active set"
		else
			word = path
		end
		table.insert(words, word)
	end
	return table.concat(words, ", ")
end

local function itemSummary(itemId: string, stackSize: number, meta: any?): any
	local def = Registry.get(itemId) :: any
	local affixes = {}
	for _, affix in ipairs(meta and meta.affixes or {}) do
		if type(affix) == "table" and type(affix.id) == "string" then
			table.insert(affixes, { id = affix.id, tier = affix.tier, label = affix.label })
		end
	end
	return {
		itemId = itemId,
		name = (meta and meta.displayName) or (def and def.name) or itemId,
		count = stackSize,
		rarity = meta and meta.rarity,
		itemLevel = meta and meta.itemLevel,
		affixes = affixes,
		stackLimit = if def and def.stackLimit and def.stackLimit > 0 then def.stackLimit else 1,
	}
end

-- Everything still missing, so one reading says the whole way to open it.
local function lockReason(node: any, trackId: string, branches: { [string]: number }, attuned: boolean): string?
	local missing: { string } = {}
	if not MasteryTree.isUnlocked(node, branches, attuned) then
		local _, _, byXp = Schema.requirement(node, trackId)
		table.insert(missing, `{trackId} {byXp}`)
	end
	if not MasteryTree.isActive(node, trackId, attuned) then
		table.insert(missing, `{trackId} attuned`)
	end
	return if #missing > 0 then `needs {table.concat(missing, " and ")}` else nil
end

-- What the editor shows besides the spec: level and XP, every track's progress, pools now, slots,
-- the bag and gear as rows, and which forms and passives are open (and why not).
function Editor.readouts(player: Player, entityId: string, spec: Spec): { [string]: any }
	local out: { [string]: any } = {}
	local data = PlayerDataService.get(player)
	if not data then
		return out
	end

	local xp = data.character.xp
	local progress = CharacterXP.progressOf(xp)
	out.level = progress.level
	out.xp = xp
	out.xpInto = progress.into
	out.xpToNext = if progress.needed then progress.needed - progress.into else nil
	out.levelFloor = CharacterXP.totalFor(progress.level)

	local saved = AttributesManager.toSaved(player)
	local attributes: { [string]: number } = {}
	for _, name in ipairs(AttributeTypes.AllAttributeNames) do
		attributes[name] = if saved then saved.base[name] or 0 else 0
	end
	out.attributes = attributes
	out.unspent = if saved then saved.availablePoints else 0

	local attunedList = progression("AttunementService").attunedOf(data)
	local masteries = progression("MasteryService").masteriesOf(data)
	local tracks: { [string]: any } = {}
	for _, track in ipairs(MasteryTracks.list()) do
		local branches = masteries[track.id] or {}
		tracks[track.id] = {
			level = MasteryXP.levelOf(MasteryXP.totalOf(branches)),
			trunk = branches.trunk or 0,
			a = branches.a or 0,
			b = branches.b or 0,
			ranks = {
				trunk = MasteryXP.rankOf("trunk", branches),
				a = MasteryXP.rankOf("a", branches),
				b = MasteryXP.rankOf("b", branches),
			},
			attuned = table.find(attunedList, track.id) ~= nil,
		}
	end
	out.masteries = tracks
	out.attunement = {
		tracks = attunedList,
		used = #attunedList,
		slots = Attunement.slotsFor(progress.level),
		nextSlotLevel = Attunement.nextSlotLevel(progress.level),
	}

	local pools: { [string]: any } = {}
	local held = Holds.heldOf(player)
	for _, pool in ipairs(Schema.build().pools) do
		local current = StatsManager.getPoolCurrentValue(entityId, pool :: any)
		local max = StatsManager.getPoolMaxValue(entityId, pool :: any)
		if current and max then
			pools[pool] = { current = current, max = max, held = held[pool] }
		end
	end
	out.pools = pools

	out.skills = (spec :: any).skills or {}
	local sets = {}
	for _, set in ipairs(data.loadout.sets) do
		table.insert(sets, table.clone(set.slots))
	end
	out.bar = sets
	out.activeSet = data.loadout.activeSet

	local inventory = InventoryService.serialize(entityId)
	local equipment: { [string]: any } = {}
	local bag = {}
	local mainItemId: string? = nil
	if inventory then
		for slot, uid in pairs(inventory.equipment) do
			local item = inventory.items[uid]
			if item then
				equipment[slot] = itemSummary(item.itemId, item.stackSize, item.meta)
				if slot == "Main" then
					mainItemId = item.itemId
				end
			end
		end
		-- In the order Characters.capture lists the bag, so `keep = i` in a patch names row i.
		for slot, uid in ipairs(inventory.slots) do
			local item = if uid ~= "" then inventory.items[uid] else nil
			if item then
				local row = itemSummary(item.itemId, item.stackSize, item.meta)
				row.slot = slot
				table.insert(bag, row)
			end
		end
		out.capacity = inventory.capacity
	end
	out.equipment = equipment
	out.bag = bag

	-- Forms: every shape per weapon class, the infusions and the selectable passives, each with why
	-- it is locked when it is.
	local mainDef = if mainItemId then Registry.get(mainItemId) else nil
	local mainWeapon = mainDef and EquipmentDefUtils.getWeapon(mainDef)
	local granted = mainWeapon and mainWeapon.grantsShapes or {}
	local classes: { [string]: any } = {}
	for _, classKey in ipairs(Schema.classKeys()) do
		local options = {}
		for _, profile in ipairs(BasicAttackProfileRegistry.shapesFor(classKey)) do
			local reason: string? = nil
			if table.find(granted, profile.id) then
				reason = nil
			elseif not MasteryTree.isShapeUnlocked(profile.id, masteries, attunedList) then
				local node, tree = MasteryTrees.nodeForShape(profile.id)
				reason = if node and tree
					then lockReason(node, tree.track, masteries[tree.track] or {}, table.find(attunedList, tree.track) ~= nil)
						or "locked"
					else "no mastery node unlocks it"
			end
			table.insert(options, { id = profile.id, name = profile.displayName, locked = reason })
		end
		local default = if classKey == "unarmed"
			then BasicAttackProfileRegistry.getUnarmedProfile()
			else BasicAttackProfileRegistry.resolveForWeapon(nil, classKey, nil)
		classes[classKey] = {
			selected = data.progression.shapes[classKey],
			default = default.displayName,
			options = options,
		}
	end
	local infusions = {}
	local passives = {}
	for _, track in ipairs(MasteryTracks.list()) do
		local tree = MasteryTrees.get(track.id)
		local branches = masteries[track.id] or {}
		local attuned = table.find(attunedList, track.id) ~= nil
		for _, node in ipairs(tree and tree.nodes or {}) do
			if node.kind == "infusion" then
				table.insert(infusions, { id = node.id, name = node.displayName, locked = lockReason(node, track.id, branches, attuned) })
			elseif node.kind == "select" then
				table.insert(passives, { id = node.id, name = node.displayName, track = track.id, locked = lockReason(node, track.id, branches, attuned) })
			end
		end
	end
	local chosen = {}
	local passiveSlots = PassivePool.slotsFor(progress.level)
	for _, nodeId in ipairs(data.progression.passives) do
		if #chosen < passiveSlots then
			table.insert(chosen, nodeId)
		end
	end
	local nextPassiveLevel: number? = nil
	for _, level in ipairs(PassivePool.SLOT_LEVELS) do
		if progress.level < level then
			nextPassiveLevel = level
			break
		end
	end
	out.forms = {
		classes = classes,
		infusion = { selected = data.progression.infusion, options = infusions },
		passives = {
			selected = chosen,
			used = #chosen,
			slots = passiveSlots,
			nextSlotLevel = nextPassiveLevel,
			options = passives,
		},
	}

	out.stats = (spec :: any).stats or {}
	out.slotsPerSet = LoadoutTypes.SLOTS_PER_SET
	return out
end

return Editor
