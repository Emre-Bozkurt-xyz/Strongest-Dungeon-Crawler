--!strict
-- Characters: put a declared character on a live player, as often as wanted in one session, without
-- touching their real save.
--
-- A spec (Types) describes a character; named ones are the modules in Presets, the preset's name
-- being the module's. Applying one builds a save from a brand-new template plus the spec, puts it in
-- place of the player's own (PlayerDataService sandbox) and rebuilds the player from it
-- (PlayerSession.reload), then sets what no save holds: owned skills, base stat overrides, starting
-- pools. Every apply starts from that clean template, never from the character before it, so the
-- same spec always gives the same character.
--
-- `restore` goes back to the real save, untouched since the first apply, and to the skills and base
-- stat values the player had before it. Anything earned while sandboxed is discarded, on restore or
-- on leaving the game; items dropped in the world are kept to the save they came from (Drops).

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AttributeTypes = require(ReplicatedStorage.Shared.AttributeTypes)
local CharacterXP = require(ReplicatedStorage.Shared.progression.CharacterXP)
local Attunement = require(ReplicatedStorage.Shared.progression.Attunement)
local PassivePool = require(ReplicatedStorage.Shared.progression.PassivePool)
local MasteryTree = require(ReplicatedStorage.Shared.progression.MasteryTree)
local MasteryTracks = require(ReplicatedStorage.Shared.progression.MasteryTracks)
local LoadoutTypes = require(ReplicatedStorage.Shared.skills.LoadoutTypes)
local Registry = require(ReplicatedStorage.Shared.items.Registry)

local Server = ServerScriptService.Server
local PlayerDataService = require(Server.PlayerData.PlayerDataService)
local PlayerDataSchema = require(Server.PlayerData.PlayerDataSchema)
local PlayerSession = require(Server.PlayerData.PlayerSession)
local Registrar = require(Server.Services.Registrar)
local StatsManager = require(Server.Stats.StatsManager)
local StatsConfig = require(Server.Stats.Config.StatsConfig)
local AttributesManager = require(Server.Stats.AttributesManager)
local SkillsManager = require(Server.SkillsFramework.SkillsManager)
local SkillMetadataService = require(Server.SkillsFramework.SkillMetadataService)
local InventoryService = require(Server.Inventory.InventoryService)
local EquipmentProjectionService = require(Server.Inventory.Projection.EquipmentProjectionService)

local Types = require(script.Types)
local Specs = require(script.Specs)
local Serialize = require(script.Serialize)
local Drops = require(script.Drops)

export type Spec = Types.Spec

local Characters = {}

local REFILLED_POOLS = { "Health", "Mana", "Stamina" }
local CUSTOM = "custom"
local DEFAULT_CAPACITY = PlayerDataSchema.template().inventory.capacity

-- Preset name (or "custom") applied to each sandboxed player.
local currentName: { [Player]: string } = {}
-- Owned skills before the first apply, given back on restore.
local skillsBefore: { [Player]: { string } } = {}
-- Base value each overridden stat had before the first override of it, put back when no spec
-- overrides it any more.
local baseBefore: { [Player]: { [string]: number } } = {}
-- A change in progress; reload yields, and two at once would interleave.
local busy: { [Player]: boolean } = {}

-- Runs right before a player's save is swapped (onto a preset or back to the real save), while the
-- old save is still in use.
local function beforeSwap(player: Player)
	local ok, err = pcall(Drops.beforeSwap, player)
	if not ok then
		warn(`[Characters] settling drops failed: {err}`)
	end
end

-- Which save a world drop belongs to (see Drops), settling it now if it has not been yet. Nil for
-- anything that is not a drop.
function Characters.dropOrigin(drop: Instance): Drops.Origin?
	return Drops.origin(drop)
end

-- Characters captured with `save` this session, by name, as specs and as the Luau source to paste
-- into Presets. The game cannot write repository files, so these last until the server stops; a
-- session preset hides a preset file of the same name, being the newer of the two.
type SessionPreset = { spec: Spec, source: string }
local sessionPresets: { [string]: SessionPreset } = {}

local function presetModule(name: string): ModuleScript?
	local module = script.Presets:FindFirstChild(name)
	return if module and module:IsA("ModuleScript") then module else nil
end

local function rawPreset(name: string): any?
	local session = sessionPresets[name]
	if session then
		return session.spec
	end
	local module = presetModule(name)
	if not module then
		return nil
	end
	local ok, value = pcall(require, module)
	return if ok then value else nil
end

-- Preset names, files and session captures together, sorted.
function Characters.list(): { string }
	local names: { string } = {}
	for _, child in ipairs(script.Presets:GetChildren()) do
		if child:IsA("ModuleScript") then
			table.insert(names, child.Name)
		end
	end
	for name in pairs(sessionPresets) do
		if not table.find(names, name) then
			table.insert(names, name)
		end
	end
	table.sort(names)
	return names
end

-- "session" for a capture saved this session, "file" for a module in Presets, nil for neither.
function Characters.presetSource(name: string): string?
	if sessionPresets[name] then
		return "session"
	end
	return if presetModule(name) then "file" else nil
end

-- The Luau source of a session capture, for reading it back.
function Characters.savedSource(name: string): string?
	local session = sessionPresets[name]
	return session and session.source
end

local function setCharacterAttribute(player: Player, name: string?)
	player:SetAttribute("DevCharacter", name or "")
end

-- The preset with `extends` resolved, or nil when there is none by that name (or it does not
-- resolve).
function Characters.get(name: string): Spec?
	local raw = rawPreset(name)
	if raw == nil then
		return nil
	end
	local spec = Specs.resolve(raw, rawPreset)
	return spec
end

local function resolveInput(specOrName: any): (Spec?, string, string?)
	if type(specOrName) == "string" then
		local raw: any
		local session = sessionPresets[specOrName]
		if session then
			raw = session.spec
		else
			local module = presetModule(specOrName)
			if not module then
				return nil, specOrName, `no preset named '{specOrName}' ({table.concat(Characters.list(), ", ")})`
			end
			local ok, value = pcall(require, module)
			if not ok then
				return nil, specOrName, `preset '{specOrName}' failed to load: {value}`
			end
			raw = value
		end
		local spec, err = Specs.resolve(raw, rawPreset, { specOrName })
		return spec, specOrName, err
	end
	local spec, err = Specs.resolve(specOrName, rawPreset)
	return spec, CUSTOM, err
end

-- Skills the player owns in their own right: everything but what equipped gear grants, which the
-- gear takes back with it.
local function ownedSkills(entityId: string): { string }
	local granted: { [string]: boolean } = {}
	local projection = EquipmentProjectionService.get(entityId)
	for _, grant in ipairs(projection and projection.grantedSkills or {}) do
		granted[grant.skillName] = true
	end
	local out: { string } = {}
	for _, name in ipairs(SkillsManager.getSkillNames(entityId)) do
		if not granted[name] then
			table.insert(out, name)
		end
	end
	return out
end

local function setOwnedSkills(entityId: string, wanted: { string })
	local current = ownedSkills(entityId)
	for _, name in ipairs(current) do
		if not table.find(wanted, name) then
			SkillsManager.removeSkill(entityId, name)
		end
	end
	for _, name in ipairs(wanted) do
		if not SkillsManager.getSkill(entityId, name) then
			SkillsManager.addSkill(entityId, name)
		end
	end
end

local function baseValueOf(entityId: string, stat: string): number?
	local instance = StatsManager.getStat(entityId, stat :: any) :: any
	return if instance and instance.getBaseValue then instance:getBaseValue() else nil
end

-- Override exactly `overrides`; every stat an earlier spec overrode and this one does not goes back
-- to its value from before.
local function setBaseStats(player: Player, entityId: string, overrides: { [string]: number })
	local before = baseBefore[player] or {}
	for stat, value in pairs(before) do
		if overrides[stat] == nil then
			StatsManager.setBaseStat(entityId, stat :: any, value)
			before[stat] = nil
		end
	end
	for stat, value in pairs(overrides) do
		if before[stat] == nil then
			before[stat] = baseValueOf(entityId, stat)
		end
		StatsManager.setBaseStat(entityId, stat :: any, value)
	end
	baseBefore[player] = if next(before) then before else nil
end

local function setPool(entityId: string, pool: string, value: number)
	local max = StatsManager.getPoolMaxValue(entityId, pool :: any)
	local current = StatsManager.getPoolCurrentValue(entityId, pool :: any)
	if not max or not current then
		return
	end
	local target = if value <= 1 then max * value else math.min(value, max)
	if target > current then
		StatsManager.addToPool(entityId, pool :: any, target - current)
	elseif target < current then
		StatsManager.removeFromPool(entityId, pool :: any, current - target)
	end
end

-- After base stats, which can move a pool's maximum: pools the spec does not name are full.
local function setPools(entityId: string, pools: { [string]: number })
	for _, pool in ipairs(REFILLED_POOLS) do
		if pools[pool] == nil then
			setPool(entityId, pool, 1)
		end
	end
	for pool, value in pairs(pools) do
		setPool(entityId, pool, value)
	end
end

local function applyResolved(player: Player, entityId: string, spec: Spec, name: string): (boolean, string?)
	local wasSandboxed = PlayerDataService.isSandboxed(player)
	if not wasSandboxed then
		skillsBefore[player] = ownedSkills(entityId)
	end
	local save = Specs.buildSave(spec)
	-- On failure there is nothing to undo: either no swap happened, or the player left.
	local ok, err = PlayerSession.reload(player, function(): boolean
		beforeSwap(player)
		return PlayerDataService.enterSandbox(player, save)
	end)
	if not ok then
		if not wasSandboxed then
			skillsBefore[player] = nil
		end
		return false, err
	end
	setOwnedSkills(entityId, spec.skills or {})
	setBaseStats(player, entityId, spec.stats or {})
	setPools(entityId, spec.pools or {})
	SkillMetadataService.updateAllSkills(player)
	currentName[player] = name
	setCharacterAttribute(player, name)
	return true, nil
end

-- Put a character on the player: a preset name, or a spec table (which may `extends` a preset).
-- The whole spec is checked first; if anything is wrong nothing is applied, and the message lists
-- every problem.
function Characters.apply(player: Player, specOrName: any): (boolean, string?)
	local spec, name, err = resolveInput(specOrName)
	if not spec then
		return false, `character '{name}': {err}`
	end
	local problems = Specs.validate(spec)
	if #problems > 0 then
		return false, `character '{name}' is invalid:\n  - {table.concat(problems, "\n  - ")}`
	end
	local entityId = Registrar.getPlayerId(player)
	if not entityId or not PlayerDataService.get(player) then
		return false, "the player's save has not loaded"
	end
	if busy[player] then
		return false, "a character change is already in progress"
	end
	busy[player] = true
	local ok, applied, message = pcall(applyResolved, player, entityId, spec, name)
	busy[player] = nil
	if not ok then
		return false, `applying '{name}' failed: {applied}`
	end
	return applied, message
end

-- Back to the player's real save and their own skills and base stats. Already there: nothing to do.
function Characters.restore(player: Player): (boolean, string?)
	if not PlayerDataService.isSandboxed(player) then
		currentName[player] = nil
		setCharacterAttribute(player, nil)
		return true, nil
	end
	local entityId = Registrar.getPlayerId(player)
	if not entityId then
		return false, "the player has no entity"
	end
	if busy[player] then
		return false, "a character change is already in progress"
	end
	busy[player] = true
	local ok, reloaded, message = pcall(function(): (boolean, string?)
		local reloadOk, err = PlayerSession.reload(player, function(): boolean
			beforeSwap(player)
			PlayerDataService.exitSandbox(player)
			return true
		end)
		if not reloadOk then
			return false, err
		end
		setOwnedSkills(entityId, skillsBefore[player] or {})
		setBaseStats(player, entityId, {})
		SkillMetadataService.updateAllSkills(player)
		return true, nil
	end)
	busy[player] = nil
	if not PlayerDataService.isSandboxed(player) then
		skillsBefore[player] = nil
		currentName[player] = nil
		setCharacterAttribute(player, nil)
	end
	if not ok then
		return false, `restoring failed: {reloaded}`
	end
	return reloaded, message
end

-- Name of the applied preset, "custom" for an inline spec, nil on the real save.
function Characters.current(player: Player): string?
	return if PlayerDataService.isSandboxed(player) then currentName[player] else nil
end

local function round(value: number, places: number): number
	local scale = 10 ^ places
	return math.floor(value * scale + 0.5) / scale
end

local function itemSpecOf(itemId: string, stackSize: number, meta: any?, inBag: boolean): any
	local def = Registry.get(itemId)
	local stackable = def ~= nil and (def.stackLimit or 1) > 1
	local out: { [any]: any } = { itemId }
	if inBag and (stackable or stackSize > 1) then
		out[2] = stackSize
	end
	if meta ~= nil and next(meta) ~= nil then
		out.meta = Specs.deepCopy(meta)
	end
	if #out == 1 and out.meta == nil then
		return itemId
	end
	return out
end

-- The player's character as it is now, as a spec: `apply(capture(player))` rebuilds it. Self-
-- contained (no `extends`). A shape or infusion selection that is currently locked is left out, since
-- it does nothing; items keep their exact meta.
function Characters.capture(player: Player): Spec
	local spec: { [string]: any } = {}
	local data = PlayerDataService.get(player)
	local entityId = Registrar.getPlayerId(player)
	if not data or not entityId then
		return spec
	end

	local xp = data.character.xp
	local level = CharacterXP.levelOf(xp)
	if CharacterXP.totalFor(level) == xp then
		spec.level = level
	else
		spec.xp = xp
	end

	local saved = AttributesManager.toSaved(player)
	if saved then
		local attributes: { [string]: number } = {}
		for _, name in ipairs(AttributeTypes.AllAttributeNames) do
			local value = saved.base[name]
			if value and value ~= 0 then
				attributes[name] = value
			end
		end
		attributes.unspent = saved.availablePoints
		spec.attributes = attributes
	end

	local masteries: { [string]: { [string]: number } } = {}
	local everyTrack: { [string]: { [string]: number } } = {}
	for _, track in ipairs(MasteryTracks.list()) do
		local entry = data.progression.masteries[track.id]
		local branches: { [string]: number } = {}
		if type(entry) == "table" and type(entry.branches) == "table" then
			for branch, value in pairs(entry.branches) do
				if type(value) == "number" and value > 0 then
					branches[branch] = value
				end
			end
		end
		everyTrack[track.id] = branches
		if next(branches) then
			masteries[track.id] = branches
		end
	end
	if next(masteries) then
		spec.mastery = masteries
	end
	local attuned = Attunement.effective(data.progression.attunement, level)
	if #attuned > 0 then
		spec.attuned = attuned
	end

	spec.skills = ownedSkills(entityId)
	-- Trailing empty slots and sets are dropped; a bar equal to a new save's is left out entirely.
	local function trimmedBar(sets: { LoadoutTypes.SlotSet }): { { string } }
		local bar = {}
		for _, set in ipairs(sets) do
			local slots = table.clone(set.slots)
			while #slots > 0 and slots[#slots] == LoadoutTypes.EMPTY do
				table.remove(slots)
			end
			table.insert(bar, slots)
		end
		while #bar > 0 and #bar[#bar] == 0 do
			table.remove(bar)
		end
		return bar
	end
	local bar = trimmedBar(data.loadout.sets)
	local defaultBar = trimmedBar(PlayerDataSchema.defaultLoadout().sets)
	local isDefault = #bar == #defaultBar
	for index, slots in ipairs(bar) do
		isDefault = isDefault and table.concat(slots, "\0") == table.concat(defaultBar[index], "\0")
	end
	if not isDefault then
		spec.bar = bar
	end
	if data.loadout.activeSet ~= 1 then
		spec.activeSet = data.loadout.activeSet
	end

	local inventory = InventoryService.serialize(entityId)
	if inventory then
		local equipment: { [string]: any } = {}
		for slot, uid in pairs(inventory.equipment) do
			local item = inventory.items[uid]
			if item then
				equipment[slot] = itemSpecOf(item.itemId, item.stackSize, item.meta, false)
			end
		end
		if next(equipment) then
			spec.equipment = equipment
		end
		local bag = {}
		for slot, uid in ipairs(inventory.slots) do
			local item = if uid ~= "" then inventory.items[uid] else nil
			if item then
				local entry = itemSpecOf(item.itemId, item.stackSize, item.meta, true)
				-- Items fill the first free slots in order, so a slot is only stated where a gap
				-- before it would otherwise move the item up.
				if slot ~= #bag + 1 then
					if type(entry) == "string" then
						entry = { entry }
					end
					entry.slot = slot
				end
				table.insert(bag, entry)
			end
		end
		if #bag > 0 then
			spec.bag = bag
		end
		if inventory.capacity ~= DEFAULT_CAPACITY then
			spec.capacity = inventory.capacity
		end
	end

	local shapes: { [string]: string } = {}
	for classKey, shapeId in pairs(data.progression.shapes) do
		if MasteryTree.isShapeUnlocked(shapeId, everyTrack, attuned) then
			shapes[classKey] = shapeId
		end
	end
	if next(shapes) then
		spec.shapes = shapes
	end
	local infusion = data.progression.infusion
	if type(infusion) == "string" and infusion ~= "" and MasteryTree.isInfusionUnlocked(infusion, everyTrack, attuned) then
		spec.infusion = infusion
	end
	local passives = {}
	for _, nodeId in ipairs(data.progression.passives) do
		if #passives < PassivePool.slotsFor(level) then
			table.insert(passives, nodeId)
		end
	end
	if #passives > 0 then
		spec.passives = passives
	end

	local pools: { [string]: number } = {}
	for _, pool in ipairs(REFILLED_POOLS) do
		local max = StatsManager.getPoolMaxValue(entityId, pool :: any)
		local current = StatsManager.getPoolCurrentValue(entityId, pool :: any)
		if max and current and max > 0 and current < max - 1e-3 then
			pools[pool] = round(current / max, 3)
		end
	end
	if next(pools) then
		spec.pools = pools
	end

	local stats: { [string]: number } = {}
	for stat, default in pairs(StatsConfig.createDefaultStats() :: any) do
		local base = baseValueOf(entityId, stat)
		local defaultBase = if type(default) == "table" and default.getBaseValue then default:getBaseValue() else nil
		if base and defaultBase and base ~= defaultBase then
			stats[stat] = base
		end
	end
	if next(stats) then
		spec.stats = stats
	end

	return spec :: Spec
end

function Characters.toLuau(spec: Spec): string
	return Serialize.toLuau(spec :: any)
end

-- Captures the player's character as a session preset named `name` (see sessionPresets) and returns
-- its Luau source. Applying `name` later this session gives this character back.
function Characters.save(player: Player, name: string): string
	local spec = Characters.capture(player)
	local source = Characters.toLuau(spec)
	sessionPresets[name] = { spec = Specs.deepCopy(spec), source = source }
	return source
end

function Characters.start()
	local function track(player: Player)
		if player:GetAttribute("DevCharacter") == nil then
			setCharacterAttribute(player, nil)
		end
	end
	Players.PlayerAdded:Connect(track)
	for _, player in ipairs(Players:GetPlayers()) do
		track(player)
	end

	Drops.start()
	Players.PlayerRemoving:Connect(function(player)
		Drops.release(player)
		currentName[player] = nil
		skillsBefore[player] = nil
		baseBefore[player] = nil
		busy[player] = nil
	end)
end

return Characters
