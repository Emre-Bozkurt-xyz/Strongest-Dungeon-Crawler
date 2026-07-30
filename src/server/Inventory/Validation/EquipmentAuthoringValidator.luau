--!strict
-- Validates item/equipment authoring contracts during server startup.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Registry = require(ReplicatedStorage.Shared.items.Registry)
local VisualProfileRegistry = require(ReplicatedStorage.Shared.items.VisualProfileRegistry)
local EquipmentDefUtils = require(ReplicatedStorage.Shared.items.EquipmentDefUtils)
local RigSocketRegistry = require(ReplicatedStorage.Shared.items.RigSocketRegistry)
local AffixRegistry = require(ReplicatedStorage.Shared.items.AffixRegistry)
local ItemTypes = require(ReplicatedStorage.Shared.items.ItemTypes)
local ItemEnums = require(ReplicatedStorage.Shared.items.ItemEnums)
local BasicAttackProfileRegistry = require(ReplicatedStorage.Shared.skills.BasicAttackProfileRegistry)

export type ValidationReport = {
	errors: { string },
	warnings: { string },
}

local EquipmentAuthoringValidator = {}

local function push(report: ValidationReport, severity: "error" | "warning", message: string)
	if severity == "error" then
		table.insert(report.errors, message)
	else
		table.insert(report.warnings, message)
	end
end

local function getItemAsset(assetName: string): Instance?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local items = assets and assets:FindFirstChild("Items")
	if not items then
		return nil
	end
	return items:FindFirstChild(assetName)
end

local function findAttachment(root: Instance, attachmentName: string): Attachment?
	for _, node in ipairs(root:GetDescendants()) do
		if node:IsA("Attachment") and node.Name == attachmentName then
			return node
		end
	end
	return nil
end

local function validateBinding(
	report: ValidationReport,
	scope: string,
	rigId: string,
	binding: ItemTypes.SocketedVisualBinding | ItemTypes.SegmentedVisualBinding
)
	local socket, canonicalName = RigSocketRegistry.getSocket(rigId, binding.characterSocket)
	if not socket or not canonicalName then
		push(report, "error", `{scope}: unknown character socket '{binding.characterSocket}' for rig '{rigId}'`)
	else
		if binding.characterSocket ~= canonicalName then
			push(
				report,
				"warning",
				`{scope}: uses legacy character socket alias '{binding.characterSocket}'; prefer canonical '{canonicalName}'`
			)
		end
	end

	local asset = getItemAsset(binding.asset)
	if not asset then
		push(report, "error", `{scope}: missing asset '{binding.asset}' in ReplicatedStorage.Assets.Items`)
		return
	end

	-- Bound to a local because `binding` is a union of two binding types, so reading .assetSocket
	-- repeatedly yields `(string | string)?`, which Luau will not narrow across the `and` chain.
	local assetSocket = binding.assetSocket
	if assetSocket and assetSocket ~= "" and not findAttachment(asset, assetSocket) then
		push(report, "error", `{scope}: asset '{binding.asset}' missing attachment '{assetSocket}'`)
	end
end

local function validateProfile(report: ValidationReport, profile: ItemTypes.EquipmentVisualProfile)
	if not RigSocketRegistry.getProfile(profile.rig) then
		push(report, "error", `visual profile '{profile.id}': unknown rig '{profile.rig}'`)
		return
	end

	if profile.mode == "socketed" then
		if not profile.socketed and not profile.socketedSlots then
			push(report, "error", `visual profile '{profile.id}': socketed profile missing binding`)
			return
		end
		if profile.socketed then
			validateBinding(report, `visual profile '{profile.id}'`, profile.rig, profile.socketed)
		end
		if profile.socketedSlots then
			for slotName, binding in pairs(profile.socketedSlots) do
				validateBinding(report, `visual profile '{profile.id}' slot '{slotName}'`, profile.rig, binding)
			end
		end
		return
	end

	if profile.mode == "segmented" then
		local segments = profile.segments
		local segmentsBySlot = profile.segmentsBySlot
		if not segments and not segmentsBySlot then
			push(report, "error", `visual profile '{profile.id}': segmented profile missing segments`)
			return
		end
		if segments then
			for segmentName, binding in pairs(segments) do
				validateBinding(report, `visual profile '{profile.id}' segment '{segmentName}'`, profile.rig, binding)
			end
		end
		if segmentsBySlot then
			for slotName, slotSegments in pairs(segmentsBySlot) do
				for segmentName, binding in pairs(slotSegments) do
					validateBinding(
						report,
						`visual profile '{profile.id}' slot '{slotName}' segment '{segmentName}'`,
						profile.rig,
						binding
					)
				end
			end
		end
		return
	end

	if profile.mode == "skinned" then
		local binding = profile.skinned
		if not binding then
			push(report, "error", `visual profile '{profile.id}': skinned profile missing binding`)
			return
		end
		local asset = getItemAsset(binding.asset)
		if not asset then
			push(report, "error", `visual profile '{profile.id}': missing skinned asset '{binding.asset}'`)
		end
		if binding.anchorSocket and binding.anchorSocket ~= "" then
			local socket, canonicalName = RigSocketRegistry.getSocket(profile.rig, binding.anchorSocket)
			if not socket or not canonicalName then
				push(report, "error", `visual profile '{profile.id}': unknown anchor socket '{binding.anchorSocket}'`)
			elseif binding.anchorSocket ~= canonicalName then
				push(
					report,
					"warning",
					`visual profile '{profile.id}': uses legacy anchor socket alias '{binding.anchorSocket}'; prefer '{canonicalName}'`
				)
			end
		end
	end
end

local function containsString(values: { ItemTypes.EquipSlot }?, wanted: string): boolean
	if not values then
		return false
	end
	for _, value in ipairs(values) do
		if value == wanted then
			return true
		end
	end
	return false
end

local function validateAllowedSlots(
	report: ValidationReport,
	scope: string,
	equipmentSlots: { ItemTypes.EquipSlot },
	allowedSlots: { ItemTypes.EquipSlot }?
)
	if not allowedSlots then
		return
	end

	if #allowedSlots == 0 then
		push(report, "error", `{scope}: allowedSlots must not be empty when provided`)
		return
	end

	for _, slotName in ipairs(allowedSlots) do
		if not containsString(equipmentSlots, slotName) then
			push(report, "error", `{scope}: allowed slot '{slotName}' is not listed in equipment.slots`)
		end
	end
end

-- Enforced here as well as by the type checker because item defs reach the Registry through
-- `require`: a def authored without ItemEnums, or with `:: any` anywhere in the chain, can carry a
-- value the union would have rejected.
local function validateEnumValue(
	report: ValidationReport,
	scope: string,
	field: string,
	value: string,
	isValid: (string) -> boolean,
	legalValues: { string }
)
	if not isValid(value) then
		push(
			report,
			"error",
			`{scope}: {field} '{value}' is not a known value. Legal values: {table.concat(legalValues, ", ")}`
		)
	end
end

-- Returns the first socketed binding's asset; every slot of a given weapon points at the same asset
-- in practice, and validateProfile catches a per-slot mismatch.
local function getWeaponAssetName(def: ItemTypes.ItemDef): string?
	local profileId = EquipmentDefUtils.getVisualProfileId(def)
	if not profileId then
		return nil
	end
	local profile = VisualProfileRegistry.get(profileId)
	if not profile then
		return nil
	end
	if profile.socketed then
		return profile.socketed.asset
	end
	if profile.socketedSlots then
		for _, binding in pairs(profile.socketedSlots) do
			return binding.asset
		end
	end
	return nil
end

-- A weapon whose basic attack profile fires projectiles must be able to fire one. Otherwise the
-- failure only shows up as a warn mid-combat, where BasicAttack degrades to a cone hit -- a wand
-- swinging at melee range is worth hearing about at startup rather than in playtest.
local function validateWeaponProjectile(report: ValidationReport, def: ItemTypes.ItemDef, weapon: ItemTypes.WeaponConfig)
	local scope = `item '{def.id}' weapon`
	local profile = BasicAttackProfileRegistry.resolveForWeapon(weapon.basicAttackProfile, weapon.class, def.id)
	local profileFiresProjectiles = BasicAttackProfileRegistry.hasProjectileStep(profile)
	local projectile = weapon.projectile

	if profileFiresProjectiles and not projectile then
		push(
			report,
			"error",
			`{scope}: resolves to basic attack profile '{profile.id}', which has projectile-delivery steps,`
				.. ` but the weapon declares no projectile config. Those steps would fall back to a cone hit.`
		)
		return
	end

	if projectile and not profileFiresProjectiles then
		push(
			report,
			"warning",
			`{scope}: declares a projectile but resolves to basic attack profile '{profile.id}', which has no`
				.. ` projectile-delivery steps, so it will never be fired.`
		)
	end

	if not projectile then
		return
	end

	if projectile.templateKey == "" then
		push(report, "error", `{scope}: projectile.templateKey is required`)
	end
	if projectile.launchSpeed <= 0 then
		push(report, "error", `{scope}: projectile.launchSpeed must be greater than 0`)
	end
	if projectile.lifetime <= 0 then
		push(report, "error", `{scope}: projectile.lifetime must be greater than 0`)
	end

	-- BasicAttack has no fallback origin, so a missing muzzle costs the step its projectile.
	if projectile.muzzleSocket == "" then
		push(report, "error", `{scope}: projectile.muzzleSocket is required`)
		return
	end
	local assetName = getWeaponAssetName(def)
	if not assetName then
		push(
			report,
			"warning",
			`{scope}: declares projectile.muzzleSocket '{projectile.muzzleSocket}' but the item has no socketed`
				.. ` visual profile, so the attachment cannot be verified`
		)
		return
	end
	local asset = getItemAsset(assetName)
	if not asset then
		-- validateProfile already reports the missing asset itself; don't double-report.
		return
	end
	if not findAttachment(asset, projectile.muzzleSocket) then
		push(
			report,
			"error",
			`{scope}: asset '{assetName}' is missing Attachment '{projectile.muzzleSocket}' named by`
				.. ` projectile.muzzleSocket. Add it where the projectile should appear (the weapon's tip);`
				.. ` its rotation does not matter, aim comes from the player's cursor.`
		)
	end
end

local function validateWeapon(report: ValidationReport, def: ItemTypes.ItemDef, weapon: ItemTypes.WeaponConfig)
	local scope = `item '{def.id}' weapon`

	validateEnumValue(report, scope, "class", weapon.class, ItemEnums.isWeaponClass, ItemEnums.listWeaponClasses())

	if weapon.handedness ~= "one_handed" and weapon.handedness ~= "two_handed" then
		push(report, "error", `{scope}: handedness must be 'one_handed' or 'two_handed'`)
	end

	if weapon.base.attackSpeed <= 0 then
		push(report, "error", `{scope}: base.attackSpeed must be greater than 0`)
	end

	if not weapon.damage or #weapon.damage == 0 then
		push(report, "error", `{scope}: damage must contain at least one roll`)
	else
		for index, damage in ipairs(weapon.damage) do
			validateEnumValue(
				report,
				scope,
				`damage[{index}].type`,
				damage.type,
				ItemEnums.isDamageType,
				ItemEnums.listDamageTypes()
			)
			if damage.min > damage.max then
				push(report, "error", `{scope}: damage[{index}] has min > max`)
			end
		end
	end

	if def.equipment then
		validateAllowedSlots(report, scope, def.equipment.slots, weapon.allowedSlots)
		if weapon.handedness == "two_handed" and not containsString(def.equipment.slots, "Main") then
			push(report, "error", `{scope}: two-handed weapons must be equippable in Main`)
		end
	end

	validateWeaponProjectile(report, def, weapon)
end

local function validateOffhand(report: ValidationReport, def: ItemTypes.ItemDef, offhand: ItemTypes.OffhandConfig)
	local scope = `item '{def.id}' offhand`

	validateEnumValue(report, scope, "type", offhand.type, ItemEnums.isOffhandType, {
		"shield",
		"quiver",
		"catalyst",
		"focus",
		"utility",
	})

	if def.equipment then
		validateAllowedSlots(report, scope, def.equipment.slots, offhand.allowedSlots)

		-- An offhand is defined by contesting the Secondary slot against a second weapon. One that
		-- cannot go there resolves to neither a weapon nor an offhand in the combat loadout, leaving
		-- it inert in combat while still looking equipped.
		if not containsString(def.equipment.slots, "Secondary") then
			push(
				report,
				"error",
				`{scope}: offhand items must be equippable in Secondary, but equipment.slots is`
					.. ` [{table.concat(def.equipment.slots, ", ")}]`
			)
		end
	end
end

local function validateDef(report: ValidationReport, def: ItemTypes.ItemDef)
	if not EquipmentDefUtils.isEquipment(def) then
		return
	end

	if not def.equipment then
		push(report, "warning", `item '{def.id}': still relies on legacy equipment fields only`)
		return
	end

	local scope = `item '{def.id}'`

	if not def.equipment.class then
		push(report, "error", `{scope}: equipment.class is required`)
	else
		validateEnumValue(
			report,
			scope,
			"equipment.class",
			def.equipment.class,
			ItemEnums.isEquipmentClass,
			ItemEnums.listEquipmentClasses()
		)
	end

	if not def.equipment.slots or #def.equipment.slots == 0 then
		push(report, "error", `{scope}: equipment.slots must contain at least one slot`)
	else
		for index, slotName in ipairs(def.equipment.slots) do
			validateEnumValue(
				report,
				scope,
				`equipment.slots[{index}]`,
				slotName,
				ItemEnums.isEquipSlot,
				ItemEnums.listEquipSlots()
			)
		end
	end

	if def.equipment.affixContext then
		validateEnumValue(
			report,
			scope,
			"equipment.affixContext",
			def.equipment.affixContext,
			ItemEnums.isAffixContext,
			ItemEnums.listAffixContexts()
		)
	end

	-- An item whose affix context has no entries rolls only "any" modifiers, which reads as "affixes
	-- are broken" rather than "this pool is unwritten". A warning, since an unwritten pool is a
	-- legitimate mid-development state.
	local context = AffixRegistry.getContext(def)
	local contextHasAffixes = false
	for _, affixDef in ipairs(AffixRegistry.list()) do
		for _, tier in ipairs(affixDef.tiers) do
			if tier.modifiersByContext[context] then
				contextHasAffixes = true
				break
			end
		end
		if contextHasAffixes then
			break
		end
	end
	if not contextHasAffixes then
		push(
			report,
			"warning",
			`{scope}: affix context '{context}' has no affix entries authored for it, so this item can only`
				.. ` roll modifiers from the 'any' context`
		)
	end

	if type(def.equipment.itemLevel) ~= "number" or def.equipment.itemLevel < 1 then
		push(report, "error", `item '{def.id}': equipment.itemLevel must be a positive number`)
	end

	if def.equipment.requirements and def.equipment.requirements.level ~= nil then
		push(
			report,
			"warning",
			`item '{def.id}': requirements.level is not enforced (no progression system exists yet; see D5)`
		)
	end

	if def.equipment.baseRolls then
		for _, roll in ipairs(def.equipment.baseRolls) do
			if roll.min > roll.max then
				push(report, "error", `item '{def.id}': base roll '{roll.target}' has min > max`)
			end
		end
	end

	if def.equipment.weapon then
		validateWeapon(report, def, def.equipment.weapon)
	end

	if def.equipment.offhand then
		validateOffhand(report, def, def.equipment.offhand)
	end

	if def.equipment.visualProfileId then
		if not VisualProfileRegistry.get(def.equipment.visualProfileId) then
			push(report, "error", `item '{def.id}': missing visual profile '{def.equipment.visualProfileId}'`)
		end
	end

	if def.equipment and (def.equipSlots or def.baseStats or def.requirements or def.visuals) then
		push(report, "warning", `item '{def.id}': still carries legacy equipment fields during migration`)
	end
end

-- Weapon-local stats (see the "Projected Equipment Effects vs Local Weapon Stats" section of the
-- architecture doc). An affix modifier that targets one of these inside a weapon context but has
-- no explicit `scope` would silently project into global player stats (the Guardrail 7 bug this
-- refactor fixes) -- fail fast instead of inferring.
local function isWeaponContext(context: string): boolean
	return string.find(context, "weapon", 1, true) ~= nil
end

local function validateAffixScopes(report: ValidationReport)
	for _, affixDef in ipairs(AffixRegistry.list()) do
		for _, tier in ipairs(affixDef.tiers) do
			for context, rollDefs in pairs(tier.modifiersByContext) do
				for _, rollDef in ipairs(rollDefs) do
					local scopeLabel = `affix '{affixDef.id}' tier {tier.tier} context '{context}'`

					-- The "any" bucket rolls on every item type, so a weapon-local target there is
					-- wrong in both directions: unscoped it leaks into global player stats when it
					-- lands on a weapon, and scoped it silently does nothing when it lands on
					-- armour. Weapon-local targets belong in a weapon context.
					if context == "any" and EquipmentDefUtils.isWeaponLocalTarget(rollDef.target) then
						push(
							report,
							"error",
							`{scopeLabel}: target '{rollDef.target}' is weapon-local and cannot live in the "any"`
								.. ` bucket, which rolls on armour too. Move it to a weapon context (e.g. melee_weapon,`
								.. ` magic_weapon) with scope = "weapon".`
						)
					end

					-- Missing scope on a weapon-local target inside a weapon context: it would
					-- default to "global" and leak into player stats (the Guardrail 7 bug).
					if
						isWeaponContext(context)
						and EquipmentDefUtils.isWeaponLocalTarget(rollDef.target)
						and rollDef.scope == nil
					then
						push(
							report,
							"error",
							`{scopeLabel}: target '{rollDef.target}' is weapon-local and requires an explicit scope (expected scope = "weapon")`
						)
					end

					-- Explicitly weapon-scoped, but CombatLoadoutResolver has nothing to apply it
					-- to. Without this the modifier rolls, replicates, and does nothing at all.
					if rollDef.scope == "weapon" and not EquipmentDefUtils.isWeaponLocalTarget(rollDef.target) then
						push(
							report,
							"error",
							`{scopeLabel}: target '{rollDef.target}' is scope = "weapon" but is not weapon-local, so it would never be applied. Supported: <Type>Damage, AttackSpeed, CriticalHitChance`
						)
					end
				end
			end
		end
	end
end

function EquipmentAuthoringValidator.validateAll(): ValidationReport
	local report: ValidationReport = {
		errors = {},
		warnings = {},
	}

	for _, def in ipairs(Registry.list()) do
		validateDef(report, def)
	end

	for _, profile in ipairs(VisualProfileRegistry.list()) do
		validateProfile(report, profile)
	end

	validateAffixScopes(report)

	return report
end

return EquipmentAuthoringValidator
