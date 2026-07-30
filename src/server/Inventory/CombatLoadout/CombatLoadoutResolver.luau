--!strict
-- Resolves equipped weapon/offhand state into a combat-facing loadout snapshot.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemTypes = require(ReplicatedStorage.Shared.items.ItemTypes)
local ItemEnums = require(ReplicatedStorage.Shared.items.ItemEnums)
local Registry = require(ReplicatedStorage.Shared.items.Registry)
local EquipmentDefUtils = require(ReplicatedStorage.Shared.items.EquipmentDefUtils)

local CombatLoadoutResolver = {}

local function cloneArray<T>(source: { T }?): { T }
	if not source then
		return {}
	end
	return table.clone(source)
end

-- Gather every scope = "weapon" modifier attached to this specific item instance (rolled base
-- modifiers + affixes). Scope "weapon" means "applies to the item it is attached to", nothing
-- else -- these must never be projected into global player stats (that's CapabilityResolver's job
-- for "global"/"attribute" scoped entries only).
local function collectWeaponScopedModifiers(def: ItemTypes.ItemDef, inst: ItemTypes.ItemInstance): { ItemTypes.ModifierEntry }
	local out: { ItemTypes.ModifierEntry } = {}

	for _, entry in ipairs(EquipmentDefUtils.getBaseModifiers(def, inst)) do
		if EquipmentDefUtils.isWeaponScope(EquipmentDefUtils.resolveScope(entry)) then
			table.insert(out, entry)
		end
	end

	local meta = inst.meta
	local affixes = meta and meta.affixes
	if affixes then
		for _, affix in ipairs(affixes) do
			local anyAffix = affix :: any
			if type(anyAffix) == "table" and anyAffix.modifiers then
				for _, entry in ipairs(anyAffix.modifiers) do
					if EquipmentDefUtils.isWeaponScope(EquipmentDefUtils.resolveScope(entry)) then
						table.insert(out, entry)
					end
				end
			elseif anyAffix.target then
				local entry = anyAffix :: ItemTypes.ModifierEntry
				if EquipmentDefUtils.isWeaponScope(EquipmentDefUtils.resolveScope(entry)) then
					table.insert(out, entry)
				end
			end
		end
	end

	return out
end

-- Returns true when the modifier was actually consumed.
-- `damageType` is `string` rather than `DamageType` for the widening reason documented on
-- EquipmentDefUtils.isProjectedScope. weaponDamageTypeForTarget has already validated it against
-- ItemEnums.DamageType, which is what makes the cast below sound.
local function applyDamageModifier(
	damage: { ItemTypes.WeaponDamageRange },
	damageType: string,
	mod: ItemTypes.ModifierEntry
): boolean
	local matched = false
	for _, entry in ipairs(damage) do
		if entry.type == damageType then
			matched = true
			if mod.kind == "flat" then
				entry.min += mod.value
				entry.max += mod.value
			elseif mod.kind == "percent" then
				entry.min *= (1 + mod.value)
				entry.max *= (1 + mod.value)
			else
				return false
			end
		end
	end

	if matched then
		return true
	end

	-- "Adds X Fire Damage" to a weapon that deals none: create the range rather than drop the
	-- modifier. A percent modifier has nothing to scale, so it stays unconsumed and is reported.
	if mod.kind == "flat" then
		table.insert(damage, { type = damageType :: ItemTypes.DamageType, min = mod.value, max = mod.value })
		return true
	end

	return false
end

-- Fold weapon-scoped modifiers into the weapon's own damage/attackSpeed/crit. This is the only
-- place these modifiers take effect; they are intentionally invisible to global player stats.
--
-- Anything this function cannot consume is reported rather than silently dropped: a weapon-scoped
-- modifier that quietly does nothing is the exact failure class the scope work exists to remove.
-- EquipmentAuthoringValidator catches these at startup; this warn is the runtime backstop for
-- modifiers that only appear after a roll.
local function applyWeaponScopedModifiers(
	itemId: string,
	baseDamage: { ItemTypes.WeaponDamageRange },
	baseAttackSpeed: number,
	baseCritChance: number?,
	modifiers: { ItemTypes.ModifierEntry }
): ({ ItemTypes.WeaponDamageRange }, number, number?)
	local damage: { ItemTypes.WeaponDamageRange } = {}
	for _, entry in ipairs(baseDamage) do
		table.insert(damage, table.clone(entry))
	end

	local attackSpeed = baseAttackSpeed
	local attackSpeedMultiplier = 1
	local critChance = baseCritChance

	for _, mod in ipairs(modifiers) do
		local consumed = false
		local damageType = EquipmentDefUtils.weaponDamageTypeForTarget(mod.target)

		if damageType then
			consumed = applyDamageModifier(damage, damageType, mod)
		elseif mod.target == "AttackSpeed" then
			if mod.kind == "percent" then
				attackSpeedMultiplier += mod.value
				consumed = true
			elseif mod.kind == "flat" then
				attackSpeed += mod.value
				consumed = true
			end
		elseif mod.target == "CriticalHitChance" then
			if mod.kind == "flat" or mod.kind == "percent" then
				critChance = (critChance or 0) + mod.value
				consumed = true
			end
		end

		if not consumed then
			warn(
				`CombatLoadoutResolver: weapon-scoped modifier on '{itemId}' had no effect`
					.. ` (target='{mod.target}', kind='{mod.kind}', id='{mod.id or "?"}').`
					.. ` Supported: <Type>Damage, AttackSpeed, CriticalHitChance.`
			)
		end
	end

	return damage, attackSpeed * attackSpeedMultiplier, critChance
end

local function makeWeapon(
	slot: string,
	uid: string,
	inst: ItemTypes.ItemInstance,
	def: ItemTypes.ItemDef,
	weapon: ItemTypes.WeaponConfig
): ItemTypes.CombatLoadoutWeapon
	local weaponMods = collectWeaponScopedModifiers(def, inst)
	local damage, attackSpeed, critChance = applyWeaponScopedModifiers(
		inst.itemId,
		EquipmentDefUtils.getWeaponDamage(def),
		weapon.base.attackSpeed,
		weapon.base.critChance,
		weaponMods
	)

	return {
		slot = slot,
		uid = uid,
		itemId = inst.itemId,
		weaponClass = weapon.class,
		handedness = weapon.handedness,
		tags = cloneArray(weapon.tags),
		attackSpeed = attackSpeed,
		range = weapon.base.range,
		critChance = critChance,
		damage = damage,
		basicAttackProfile = weapon.basicAttackProfile,
		-- By reference: authored content that no roll mutates, unlike `damage` above.
		projectile = weapon.projectile,
	}
end

local function makeOffhand(
	slot: string,
	uid: string,
	inst: ItemTypes.ItemInstance,
	def: ItemTypes.ItemDef,
	offhand: ItemTypes.OffhandConfig
): ItemTypes.CombatLoadoutOffhand
	return {
		slot = slot,
		uid = uid,
		itemId = inst.itemId,
		offhandType = offhand.type,
		tags = cloneArray(offhand.tags),
		blockProvider = offhand.blockProvider,
		supportsWeaponClasses = cloneArray(offhand.supportsWeaponClasses),
	}
end

local function hasTag(tags: { ItemTypes.ItemTag }, wanted: string): boolean
	for _, tag in ipairs(tags) do
		if tag == wanted then
			return true
		end
	end
	return false
end

type SlotResolution = {
	kind: "weapon" | "offhand",
	weapon: ItemTypes.CombatLoadoutWeapon?,
	offhand: ItemTypes.CombatLoadoutOffhand?,
}?

-- Returns its result instead of mutating upvalues: Luau drops nil-refinement for locals that are
-- assigned inside a nested function, which previously broke the `main.handedness` read below.
local function resolveSlot(
	slotName: string,
	equip: ItemTypes.EquipmentState,
	itemGetter: (uid: string) -> ItemTypes.ItemInstance?
): SlotResolution
	local uid = equip.slots[slotName]
	if not uid then
		return nil
	end
	local inst = itemGetter(uid)
	if not inst then
		return nil
	end
	local def = Registry.get(inst.itemId)
	if not def then
		return nil
	end

	local weapon = EquipmentDefUtils.getWeapon(def)
	if weapon then
		return {
			kind = "weapon",
			weapon = makeWeapon(slotName, uid, inst, def, weapon),
			offhand = nil,
		}
	end

	local offhandConfig = EquipmentDefUtils.getOffhand(def)
	if offhandConfig then
		return {
			kind = "offhand",
			weapon = nil,
			offhand = makeOffhand(slotName, uid, inst, def, offhandConfig),
		}
	end

	return nil
end

function CombatLoadoutResolver.resolve(
	entityId: string,
	equip: ItemTypes.EquipmentState,
	itemGetter: (uid: string) -> ItemTypes.ItemInstance?
): ItemTypes.CombatLoadoutSnapshot
	local mainResolution = resolveSlot("Main", equip, itemGetter)
	local main: ItemTypes.CombatLoadoutWeapon? = nil
	if mainResolution and mainResolution.kind == "weapon" then
		main = mainResolution.weapon
	end

	local secondaryResolution = resolveSlot("Secondary", equip, itemGetter)
	local secondary: ItemTypes.CombatLoadoutSecondary? = nil
	if secondaryResolution then
		secondary = {
			kind = secondaryResolution.kind,
			weapon = secondaryResolution.weapon,
			offhand = secondaryResolution.offhand,
		}
	end

	local secondaryWeapon = secondary and secondary.weapon or nil
	local secondaryOffhand = secondary and secondary.offhand or nil

	local canDualWield = main ~= nil
		and secondaryWeapon ~= nil
		and main.handedness == "one_handed"
		and secondaryWeapon.handedness == "one_handed"

	local ranged = false
	if main and hasTag(main.tags, ItemEnums.Tag.Ranged) then
		ranged = true
	end
	if secondaryWeapon and hasTag(secondaryWeapon.tags, ItemEnums.Tag.Ranged) then
		ranged = true
	end

	return {
		entityId = entityId,
		version = 0,
		main = main,
		secondary = secondary,
		modes = {
			canBlock = secondaryOffhand ~= nil and secondaryOffhand.blockProvider == true,
			canDualWield = canDualWield,
			canRangedAttack = ranged,
		},
	}
end

return CombatLoadoutResolver
