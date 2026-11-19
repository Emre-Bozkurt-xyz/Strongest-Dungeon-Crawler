--!strict
-- Characters: put a declared character on a live player, as often as wanted in one session, without
-- touching their real save.
--
-- A spec (Types) describes a character; named ones are the modules in Presets, the preset's name
-- being the module's. Applying one builds a save from a brand-new template plus the spec, puts it in
-- place of the player's own (PlayerDataService sandbox) and rebuilds the player from it
-- (PlayerSession.reload), then sets what no save holds: owned skills, base stat overrides (exactly
-- the spec's; StatsManager keeps each stat's default behind them), starting pools. Every apply starts
-- from that clean template, never from the character before it, so the same spec always gives the
-- same character.
--
-- `restore` goes back to the real save, untouched since the first apply, to the skills the player had
-- before it, and to no base overrides: every stat back on its default. Anything earned while
-- sandboxed is discarded, on restore or on leaving the game; items dropped in the world are kept to
-- the save they came from (Drops).
--
-- Editing (`edit`): a patch is laid over the live build (Editor) and applied to the player at once.
-- Each player on a preset has a session: the base it came from (a preset, or the real save when the
-- first edit was made there) and the build right after that base was applied, which is what "edited"
-- is measured against. The first edit on the real save captures the real build and moves the player
-- onto a sandbox copy of it before anything changes, so an edit never reaches the real profile.

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
local AttributesManager = require(Server.Stats.AttributesManager)
local SkillsManager = require(Server.SkillsFramework.SkillsManager)
local SkillMetadataService = require(Server.SkillsFramework.SkillMetadataService)
local InventoryService = require(Server.Inventory.InventoryService)
local EquipmentProjectionService = require(Server.Inventory.Projection.EquipmentProjectionService)

local Types = require(script.Types)
local Specs = require(script.Specs)
local Serialize = require(script.Serialize)
local Drops = require(script.Drops)
local Saved = require(script.Saved)
local Holds = require(script.Holds)
local Schema = require(script.Schema)
local Editor = require(script.Editor)

export type Spec = Types.Spec

local Characters = {}

local REFILLED_POOLS = { "Health", "Mana", "Stamina" }
local CUSTOM = "custom"
-- The base name of a sandbox copy of the real save. Not a valid preset name, so it can never be
-- mistaken for one.
local REAL_COPY = "real save copy"
local DEFAULT_CAPACITY = PlayerDataSchema.template().inventory.capacity
-- Seconds `apply` waits for the preset store's first read before deciding a name does not exist.
local LOAD_WAIT = 5
local NAME_PATTERN = "^[%w_%-]+$"

-- What an edited build is measured against. `base` is the preset it came from (nil for a copy of
-- the real save), `baseSpec` the resolved spec applied for an inline spec, `baseCapture` the build
-- right after the base was applied, `edited` the paths changed since (Editor.pathsOf).
type Session = {
	base: string?,
	baseSpec: Spec?,
	baseCapture: Spec,
	edited: { [string]: boolean },
}
local sessions: { [Player]: Session } = {}

-- Preset name (or "custom") applied to each sandboxed player.
local currentName: { [Player]: string } = {}
-- Owned skills before the first apply, given back on restore.
local skillsBefore: { [Player]: { string } } = {}
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

-- Presets come from two places: modules in Presets (files, committed with the game) and captures
-- saved in play (Saved: a dev DataStore, or this session only without one). A saved preset never
-- takes a file preset's name, so a name always means one thing.
local function presetModule(name: string): ModuleScript?
	local module = script.Presets:FindFirstChild(name)
	return if module and module:IsA("ModuleScript") then module else nil
end

local function rawPreset(name: string): any?
	local module = presetModule(name)
	if not module then
		return Saved.get(name)
	end
	local ok, value = pcall(require, module)
	return if ok then value else nil
end

-- Preset names, files and saved captures together, sorted.
function Characters.list(): { string }
	local names: { string } = {}
	for _, child in ipairs(script.Presets:GetChildren()) do
		if child:IsA("ModuleScript") then
			table.insert(names, child.Name)
		end
	end
	for _, name in ipairs(Saved.names()) do
		if not table.find(names, name) then
			table.insert(names, name)
		end
	end
	table.sort(names)
	return names
end

-- "file" for a module in Presets, "saved" for a capture in the preset store, "session" for one kept
-- for this session only; nil for none of them.
function Characters.presetSource(name: string): string?
	if presetModule(name) then
		return "file"
	end
	return Saved.source(name)
end

-- The player attribute names the base the player is on ("" on the real save); the edited flag says
-- whether the editor has changed the build since.
local function setCharacterAttribute(player: Player, name: string?, edited: boolean?)
	player:SetAttribute("DevCharacter", name or "")
	player:SetAttribute("DevCharacterEdited", edited == true)
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
		local module = presetModule(specOrName)
		if module then
			local ok, value = pcall(require, module)
			if not ok then
				return nil, specOrName, `preset '{specOrName}' failed to load: {value}`
			end
			raw = value
		else
			-- A scenario booting on a saved preset can ask before the store has been read.
			if Saved.get(specOrName) == nil then
				Saved.awaitLoaded(LOAD_WAIT)
			end
			raw = Saved.get(specOrName)
			if raw == nil then
				return nil, specOrName, `no preset named '{specOrName}' ({table.concat(Characters.list(), ", ")})`
			end
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

-- Makes `overrides` exactly the base overrides in effect: every other override is cleared, which
-- puts that stat back on its default as the default is now.
local function setBaseOverrides(entityId: string, overrides: { [string]: number })
	for stat in pairs(StatsManager.getBaseOverrides(entityId)) do
		if overrides[stat] == nil then
			StatsManager.clearBaseOverride(entityId, stat :: any)
		end
	end
	for stat, value in pairs(overrides) do
		StatsManager.setBaseOverride(entityId, stat :: any, value)
	end
end

local function setPool(entityId: string, pool: string, value: number)
	local max = StatsManager.getPoolMaxValue(entityId, pool :: any)
	local current = StatsManager.getPoolCurrentValue(entityId, pool :: any)
	if not max or not current then
		return
	end
	-- Signed through addToPool: removeFromPool runs the cost pipeline, and setting a pool is no cost.
	local target = Holds.resolve(value, max)
	if math.abs(target - current) > 1e-3 then
		StatsManager.addToPool(entityId, pool :: any, target - current)
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
	setBaseOverrides(entityId, spec.stats or {})
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
	if ok and applied then
		sessions[player] = {
			base = name,
			baseSpec = if name == CUSTOM then spec else nil,
			baseCapture = Characters.capture(player),
			edited = {},
		}
		Holds.reapply(player)
	end
	busy[player] = nil
	if not ok then
		return false, `applying '{name}' failed: {applied}`
	end
	return applied, message
end

-- Back to the player's real save, their own skills and no base overrides. Already there: nothing to
-- do.
function Characters.restore(player: Player): (boolean, string?)
	Holds.releaseAll(player)
	if not PlayerDataService.isSandboxed(player) then
		currentName[player] = nil
		sessions[player] = nil
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
		setBaseOverrides(entityId, {})
		SkillMetadataService.updateAllSkills(player)
		return true, nil
	end)
	busy[player] = nil
	if not PlayerDataService.isSandboxed(player) then
		skillsBefore[player] = nil
		currentName[player] = nil
		sessions[player] = nil
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

	-- Exactly the overrides in effect; a stat on its default is never written down, so a captured
	-- preset follows later changes of the default.
	local stats = StatsManager.getBaseOverrides(entityId)
	if next(stats) then
		spec.stats = stats
	end

	return spec :: Spec
end

function Characters.toLuau(spec: Spec): string
	return Serialize.toLuau(spec :: any)
end

export type SaveResult = {
	ok: boolean,
	message: string,
	source: string?,
	-- "saved" when it went into the preset store, "session" when it is kept for this session only.
	storage: string?,
}

-- Captures the player's live build as a preset named `name`, in the preset store (Saved) or, without
-- one, for this session. A file preset's name is refused. On a preset, the saved preset becomes the
-- base the build is edited against.
function Characters.save(player: Player, name: string): SaveResult
	if not string.match(name, NAME_PATTERN) then
		return { ok = false, message = "a preset name is letters, digits, '-' and '_'" }
	end
	if presetModule(name) then
		return { ok = false, message = `'{name}' is a file preset (Presets/{name}.luau); pick another name` }
	end
	local spec = Characters.capture(player)
	local source = Characters.toLuau(spec)
	local persisted, why = Saved.put(name, Specs.deepCopy(spec))
	if PlayerDataService.isSandboxed(player) then
		sessions[player] = { base = name, baseCapture = spec, edited = {} }
		currentName[player] = name
		setCharacterAttribute(player, name, false)
	end
	return {
		ok = true,
		message = if persisted
			then `saved '{name}' to the preset store`
			else `saved '{name}' for this session only: the preset store is unavailable ({why})`,
		source = source,
		storage = if persisted then "saved" else "session",
	}
end

-- Removes a saved preset. File presets are refused: delete the module instead.
function Characters.delete(name: string): (boolean, string)
	if presetModule(name) then
		return false, `'{name}' is a file preset; remove Presets/{name}.luau to delete it`
	end
	local removed, why = Saved.remove(name)
	if not removed then
		return false, `no saved preset named '{name}'`
	end
	if why then
		return true, `deleted '{name}' here, but the preset store could not be updated ({why})`
	end
	return true, `deleted '{name}'`
end

export type EditResult = {
	ok: boolean,
	message: string,
	-- Validator problems keyed by spec path, when the edit was refused for them.
	problems: { Editor.Problem }?,
	-- Whether the edit was set on the live player (true) or applied by a rebuild (false).
	inPlace: boolean?,
}

local function editLocked(player: Player, entityId: string, rawPatch: any): EditResult
	local patch = Serialize.fromData(rawPatch)
	if type(patch) ~= "table" or next(patch) == nil then
		return { ok = false, message = "a patch is a non-empty JSON object of spec fields" }
	end
	local current = Characters.capture(player)
	local expanded, expandError = Editor.expand(patch, current)
	if not expanded then
		return { ok = false, message = expandError or "bad patch", problems = { { field = "bag", message = expandError or "" } } }
	end
	local merged = Editor.merge(current, expanded)
	local problems = Specs.validate(merged)
	if #problems > 0 then
		return {
			ok = false,
			message = `refused: {table.concat(problems, "; ")}`,
			problems = Editor.keyProblems(problems),
		}
	end

	local sandboxed = PlayerDataService.isSandboxed(player)
	local session = sessions[player]
	if not sandboxed or not session then
		-- The first edit on the real save: the build as it is now becomes the base of a sandbox copy.
		session = {
			base = if sandboxed then currentName[player] else nil,
			baseCapture = current,
			edited = {},
		}
	end
	local name = if session.base then session.base else REAL_COPY
	local inPlace = sandboxed and Editor.isCheap(expanded)
	if inPlace then
		Editor.applyInPlace(player, expanded, merged)
	else
		local applied, applyError = applyResolved(player, entityId, merged, name)
		if not applied then
			return { ok = false, message = `could not apply the edit: {applyError}` }
		end
		Holds.reapply(player)
		-- A pool set by this edit moves its hold along with it, rather than being put back.
		for pool, value in pairs(if type(expanded.pools) == "table" then expanded.pools else {}) do
			Holds.setPool(player, pool, if value == false then 1 else value)
		end
	end
	sessions[player] = session

	local after = Characters.capture(player)
	local touched = Editor.pathsOf(expanded, current, after)
	for _, path in ipairs(touched) do
		session.edited[path] = if Editor.differs(path, after, session.baseCapture) then true else nil
	end
	setCharacterAttribute(player, name, next(session.edited) ~= nil)
	local words = Editor.describe(touched)
	return {
		ok = true,
		message = `{if inPlace then "set" else "rebuilt with"} {if words ~= "" then words else "the edit"}`
			.. (if sandboxed then "" else " (now on a sandbox copy of your real save)"),
		inPlace = inPlace,
	}
end

-- Lays `patch` (a partial spec, Editor's rules) over the player's live build and applies it. Refused
-- whole, with problems keyed by field, when the result would not validate. On the real save it first
-- moves the player onto a sandbox copy of their build, so the real profile is never written.
function Characters.edit(player: Player, patch: any): EditResult
	local entityId = Registrar.getPlayerId(player)
	if not entityId or not PlayerDataService.get(player) then
		return { ok = false, message = "the player's save has not loaded" }
	end
	if busy[player] then
		return { ok = false, message = "a character change is already in progress" }
	end
	busy[player] = true
	local ok, result = pcall(editLocked, player, entityId, patch)
	busy[player] = nil
	if not ok then
		return { ok = false, message = `editing failed: {result}` }
	end
	return result
end

-- Back to the base as it is defined: the preset re-applied (an inline spec re-applied as it was),
-- or, for a copy of the real save, the real save itself.
function Characters.revert(player: Player): (boolean, string)
	if not PlayerDataService.isSandboxed(player) then
		return true, "already on your real save"
	end
	local session = sessions[player]
	local base = session and session.base
	if not base then
		local ok, err = Characters.restore(player)
		return ok, if ok then "back on your real save" else err or "could not restore"
	end
	local ok, err = Characters.apply(player, if base == CUSTOM and session and session.baseSpec then session.baseSpec else base)
	return ok, if ok then `reverted to {base}` else err or "could not revert"
end

-- Opens a mastery node (by id or display name): every branch below what opens it is raised to that
-- (never lowered). Says what else it needs to be in effect: attunement, a passive slot.
function Characters.unlock(player: Player, ref: string): EditResult
	local node, tree = Schema.findNode(ref)
	if not node or not tree then
		return { ok = false, message = `no mastery node '{ref}'` }
	end
	local data = PlayerDataService.get(player)
	if not data then
		return { ok = false, message = "the player's save has not loaded" }
	end
	local track = tree.track
	local requirement, needsAttunement = Schema.requirement(node, track)
	local entry = data.progression.masteries[track]
	local branches = if type(entry) == "table" and type(entry.branches) == "table" then entry.branches else {}
	local raise: { [string]: number } = {}
	for branch, need in pairs(requirement :: any) do
		if (branches[branch] or 0) < need then
			raise[branch] = need
		end
	end
	local notes: { string } = {}
	local level = CharacterXP.levelOf(data.character.xp)
	local attuned = Attunement.effective(data.progression.attunement, level)
	if needsAttunement and not table.find(attuned, track) then
		table.insert(notes, `needs {track} attuned ({#attuned} of {Attunement.slotsFor(level)} slots used)`)
	end
	if node.kind == "select" then
		local slots = PassivePool.slotsFor(level)
		table.insert(notes, `choose it in passives ({#data.progression.passives} of {slots} slots used)`)
	end
	if node.kind == "form" and not (node.shapes and #node.shapes > 0) then
		table.insert(notes, "designed but not built: no shape implements it yet")
	end
	local suffix = if #notes > 0 then `; {table.concat(notes, "; ")}` else ""
	if next(raise) == nil then
		return { ok = true, message = `{node.displayName} is already unlocked{suffix}` }
	end
	local result = Characters.edit(player, { mastery = { [track] = raise } })
	if result.ok then
		result.message = `unlocked {node.displayName} ({track}){suffix}`
	end
	return result
end

-- Sets a pool from text: "81" (an amount), "60%", "full" or "empty". Goes through `edit`, so on
-- the real save it moves onto a sandbox copy first.
function Characters.setPool(player: Player, pool: string, text: string): EditResult
	local value: number?
	local lowered = string.lower(text)
	if lowered == "full" or lowered == "max" then
		value = 1
	elseif lowered == "empty" then
		value = 0
	else
		local percent = string.match(text, "^%s*([%d%.]+)%s*%%%s*$")
		if percent and tonumber(percent) then
			value = math.clamp((tonumber(percent) :: number) / 100, 0, 1)
		else
			value = tonumber(text)
		end
	end
	if value == nil or value < 0 then
		return { ok = false, message = `'{text}' is not a pool value (81, 60%, full, empty)` }
	end
	return Characters.edit(player, { pools = { [pool] = value } })
end

-- Holds a pool at its current value (Holds), or releases it. Session tooling, not an edit: it
-- changes nothing by itself, so it never moves the player off the real save.
function Characters.hold(player: Player, pool: string, on: boolean): (boolean, string)
	if not table.find(Schema.build().pools, pool) then
		return false, `unknown pool '{pool}'`
	end
	local value = Holds.hold(player, pool, on)
	if on and not value then
		return false, `you have no {pool} pool`
	end
	return true, if value then `holding {pool} at {math.floor(value + 0.5)}` else `released {pool}`
end

-- The live build and what the editor shows about it (Editor.readouts), with where it came from.
function Characters.state(player: Player): { [string]: any }?
	local entityId = Registrar.getPlayerId(player)
	if not entityId or not PlayerDataService.get(player) then
		return nil
	end
	local spec = Characters.capture(player)
	local out = Editor.readouts(player, entityId, spec)
	local sandboxed = PlayerDataService.isSandboxed(player)
	local session = sessions[player]
	local edited: { string } = {}
	for path in pairs(session and session.edited or {}) do
		table.insert(edited, path)
	end
	table.sort(edited)
	local base = if sandboxed then (if session then session.base else currentName[player]) else nil
	out.sandboxed = sandboxed
	out.base = base or ""
	out.name = if sandboxed then (base or REAL_COPY) else ""
	out.baseSource = if not sandboxed
		then "real"
		elseif base == nil then "real copy"
		elseif base == CUSTOM then "custom"
		else Characters.presetSource(base) or "missing"
	out.edited = edited
	out.editedSummary = Editor.describe(edited)
	out.spec = Serialize.toData(spec)
	return out
end

-- Every choice and limit the editor offers (Schema).
function Characters.schema(): any
	return Schema.build()
end

-- Whether saved presets persist between sessions, and why not.
function Characters.storeStatus(): (boolean, string?)
	local why = Saved.unavailableReason()
	return why == nil, why
end

function Characters.start()
	Saved.load()
	Holds.start()
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
		busy[player] = nil
		sessions[player] = nil
	end)
end

return Characters
