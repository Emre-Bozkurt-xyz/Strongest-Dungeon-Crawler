--!strict
-- Autoloads BasicAttackProfiles/*.luau (same pattern as AffixRegistry autoloading items/Affixes),
-- validates them, indexes by id and by weapon class, and exposes the single `resolve` function
-- both client and server call to turn a CombatLoadoutSnapshot into an active profile.
--
-- D6 (profile-keyed shared spec, see docs/tasks/equipment-item-architecture.md): profiles are
-- shared content and each side resolves the active one independently from the combat loadout it
-- already holds. This module is the only place that resolution happens -- neither side
-- reimplements it (trap 4).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemTypes = require(ReplicatedStorage.Shared.items.ItemTypes)
local ItemEnums = require(ReplicatedStorage.Shared.items.ItemEnums)
local BasicAttackProfileTypes = require(script.Parent.BasicAttackProfileTypes)

type BasicAttackProfile = BasicAttackProfileTypes.BasicAttackProfile

local BasicAttackProfileRegistry = {}

local UNARMED_PROFILE_ID = "unarmed_basic"

local byId: { [string]: BasicAttackProfile } = {}
local byWeaponClass: { [string]: BasicAttackProfile } = {}
local orderedIds: { string } = {}

-- Fail fast on bad content (matches EquipmentAuthoringValidator's stance): a malformed or
-- ambiguous profile should error at startup, not produce a mystery at swing time (trap 6).
local function validateProfile(def: BasicAttackProfile, sourceName: string)
	assert(type(def.id) == "string" and def.id ~= "", `BasicAttackProfile at '{sourceName}' is missing an id`)
	assert(byId[def.id] == nil, `Duplicate BasicAttackProfile id '{def.id}'`)
	assert(
		type(def.weaponClasses) == "table",
		`BasicAttackProfile '{def.id}' missing weaponClasses (use an empty table for the unarmed fallback)`
	)
	assert(type(def.steps) == "table" and #def.steps > 0, `BasicAttackProfile '{def.id}' has no steps`)
	assert(type(def.combo) == "table", `BasicAttackProfile '{def.id}' missing combo`)
	assert(
		def.combo.steps == #def.steps,
		`BasicAttackProfile '{def.id}': combo.steps ({tostring(def.combo.steps)}) must equal #steps ({#def.steps})`
	)
	assert(
		type(def.hitCone) == "table" and type(def.hitCone.angle) == "number" and type(def.hitCone.range) == "number",
		`BasicAttackProfile '{def.id}' missing hitCone.angle/hitCone.range`
	)
	assert(
		type(def.displayName) == "string" and def.displayName ~= "",
		`BasicAttackProfile '{def.id}' missing displayName`
	)
	assert(
		type(def.cost) == "table" and type(def.cost.resource) == "string" and type(def.cost.steps) == "table",
		`BasicAttackProfile '{def.id}' missing cost.resource/cost.steps`
	)
	assert(
		#def.cost.steps == #def.steps,
		`BasicAttackProfile '{def.id}': cost.steps has {#def.cost.steps} entries for {#def.steps} steps`
	)
	for _, classKey in ipairs(def.shapeFor or {}) do
		assert(
			classKey == BasicAttackProfileTypes.UNARMED_CLASS_KEY or ItemEnums.isWeaponClass(classKey),
			`BasicAttackProfile '{def.id}': shapeFor '{classKey}' is not a weapon class or '{BasicAttackProfileTypes.UNARMED_CLASS_KEY}'`
		)
	end

	for i, step in ipairs(def.steps) do
		-- Phase C: `hand` may be nil (HandResolver decides at swing time -- D9) in addition to an
		-- authored "main"/"secondary"/"both".
		assert(
			step.hand == nil or step.hand == "main" or step.hand == "secondary" or step.hand == "both",
			`BasicAttackProfile '{def.id}' step {i}: hand must be 'main', 'secondary', 'both', or omitted, got '{tostring(step.hand)}'`
		)
		assert(
			type(step.animation) == "string" and step.animation ~= "",
			`BasicAttackProfile '{def.id}' step {i} missing animation`
		)
		assert(
			type(step.damageMultiplier) == "number",
			`BasicAttackProfile '{def.id}' step {i} missing damageMultiplier`
		)
		-- Omitted delivery means "cone" (every pre-projectile profile).
		assert(
			step.delivery == nil or step.delivery == "cone" or step.delivery == "projectile",
			`BasicAttackProfile '{def.id}' step {i}: delivery must be 'cone', 'projectile', or omitted, got '{tostring(step.delivery)}'`
		)
		-- A release marker on a cone step has nothing to release and would silently do nothing.
		assert(
			step.releaseMarker == nil or step.delivery == "projectile",
			`BasicAttackProfile '{def.id}' step {i}: releaseMarker is only meaningful on delivery = 'projectile'`
		)
		assert(
			step.knockback == nil or (type(step.knockback.distance) == "number" and step.knockback.distance > 0),
			`BasicAttackProfile '{def.id}' step {i}: knockback.distance must be a positive number`
		)
	end
end

local function registerProfile(def: BasicAttackProfile, sourceName: string)
	validateProfile(def, sourceName)
	byId[def.id] = def
	table.insert(orderedIds, def.id)
	for _, weaponClass in ipairs(def.weaponClasses) do
		-- CombatLoadoutWeapon.weaponClass only holds authored WeaponClass values, so a class outside
		-- the enum leaves this profile sitting in the registry unreachable.
		assert(
			ItemEnums.isWeaponClass(weaponClass),
			`BasicAttackProfile '{def.id}': '{weaponClass}' is not a known weapon class.`
				.. ` Known: {table.concat(ItemEnums.listWeaponClasses(), ", ")}`
		)
		local existing = byWeaponClass[weaponClass]
		assert(
			existing == nil,
			`BasicAttackProfileRegistry: weapon class '{weaponClass}' is claimed by both`
				.. ` '{existing and existing.id or "?"}' and '{def.id}'`
		)
		byWeaponClass[weaponClass] = def
	end
end

local function loadFolder(folder: Instance?)
	if not folder then
		return
	end
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("ModuleScript") then
			local def = require(child) :: BasicAttackProfile
			registerProfile(def, child:GetFullName())
		end
	end
end

loadFolder(script.Parent:FindFirstChild("BasicAttackProfiles"))

table.sort(orderedIds)

assert(
	byId[UNARMED_PROFILE_ID] ~= nil,
	`BasicAttackProfileRegistry: required profile '{UNARMED_PROFILE_ID}' is missing`
)


function BasicAttackProfileRegistry.get(id: string): BasicAttackProfile?
	return byId[id]
end

-- True when any step of this profile fires a projectile, meaning a weapon that uses the profile
-- must declare a WeaponConfig.projectile or those steps degrade to a cone at swing time.
-- EquipmentAuthoringValidator uses this to catch that pairing at startup instead.
function BasicAttackProfileRegistry.hasProjectileStep(profile: BasicAttackProfile): boolean
	for _, step in ipairs(profile.steps) do
		if step.delivery == "projectile" then
			return true
		end
	end
	return false
end

function BasicAttackProfileRegistry.list(): { BasicAttackProfile }
	local out: { BasicAttackProfile } = {}
	for _, id in ipairs(orderedIds) do
		table.insert(out, byId[id])
	end
	return out
end

-- Guaranteed to exist (asserted at module load). Used as the empty-handed fallback for weapon
-- damage resolution (BaseSkill:resolveWeaponDamage) now that CombatConfig.UNARMED is gone.
function BasicAttackProfileRegistry.getUnarmedProfile(): BasicAttackProfile
	return byId[UNARMED_PROFILE_ID]
end

-- The class key the loadout's basic attack is chosen for: the main-hand weapon's class, or
-- UNARMED_CLASS_KEY for empty hands.
function BasicAttackProfileRegistry.classKeyOf(loadout: ItemTypes.CombatLoadoutSnapshot?): string
	local main = loadout and loadout.main
	return if main then main.weaponClass else BasicAttackProfileTypes.UNARMED_CLASS_KEY
end

-- Whether `profile` can be selected as the basic attack for `classKey`.
function BasicAttackProfileRegistry.fitsClass(profile: BasicAttackProfile, classKey: string): boolean
	if classKey == BasicAttackProfileTypes.UNARMED_CLASS_KEY and profile.id == UNARMED_PROFILE_ID then
		return true
	end
	return table.find(profile.weaponClasses, classKey :: any) ~= nil
		or (profile.shapeFor ~= nil and table.find(profile.shapeFor, classKey) ~= nil)
end

-- Every shape that can be selected for `classKey`, unlocked or not, in id order.
function BasicAttackProfileRegistry.shapesFor(classKey: string): { BasicAttackProfile }
	local out: { BasicAttackProfile } = {}
	for _, id in ipairs(orderedIds) do
		if BasicAttackProfileRegistry.fitsClass(byId[id], classKey) then
			table.insert(out, byId[id])
		end
	end
	return out
end

-- Resolve which profile applies for a given combat loadout snapshot. Never returns nil.
--
-- Resolution order:
--   1. the loadout carries a selected shape that exists and fits what is held -> that shape
--      (the server has already checked it is unlocked before putting it there)
--   2. no main-hand weapon -> unarmed_basic
--   3. weapon names a basicAttackProfile id that exists -> that profile
--   4. weapon names a basicAttackProfile id that does NOT exist -> warn (trap 5: loud fallback,
--      never a silent empty combo) and fall through
--   5. weapon's class has a profile registered for it -> that profile
--   6. otherwise -> unarmed_basic
function BasicAttackProfileRegistry.resolve(loadout: ItemTypes.CombatLoadoutSnapshot?): BasicAttackProfile
	local selected = loadout and loadout.basicAttackShape
	if selected then
		local shape = byId[selected]
		if shape and BasicAttackProfileRegistry.fitsClass(shape, BasicAttackProfileRegistry.classKeyOf(loadout)) then
			return shape
		end
	end

	local main = loadout and loadout.main
	if not main then
		return byId[UNARMED_PROFILE_ID]
	end

	return BasicAttackProfileRegistry.resolveForWeapon(main.basicAttackProfile, main.weaponClass, main.itemId)
end

-- Steps 2-5 of the order above, addressable without a loadout snapshot, so
-- EquipmentAuthoringValidator can answer "which profile will this def get?" from the def alone. One
-- shared implementation: a validator with its own copy of the resolution order would eventually
-- approve items the game then resolves differently (trap 4).
function BasicAttackProfileRegistry.resolveForWeapon(
	basicAttackProfile: string?,
	weaponClass: string,
	itemIdForWarning: string?
): BasicAttackProfile
	if type(basicAttackProfile) == "string" and basicAttackProfile ~= "" then
		local found = byId[basicAttackProfile]
		if found then
			return found
		end
		warn(
			`BasicAttackProfileRegistry: weapon '{itemIdForWarning or "?"}' (class '{weaponClass}') names unknown`
				.. ` basicAttackProfile '{basicAttackProfile}'; falling back by weapon class, then to unarmed_basic`
		)
	end

	local byClass = byWeaponClass[weaponClass]
	if byClass then
		return byClass
	end

	return byId[UNARMED_PROFILE_ID]
end

return BasicAttackProfileRegistry
