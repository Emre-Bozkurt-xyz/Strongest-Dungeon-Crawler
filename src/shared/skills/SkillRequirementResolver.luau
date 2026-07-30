--!strict
-- Shared authoritative predicate for "can this skill be used with the current combat loadout?"
-- (Phase C, D8 in docs/tasks/equipment-item-architecture.md).
--
-- Both the client (preflight, client/SkillsFramework/Skills/BaseSkill.luau) and the server
-- (authoritative gate, server/SkillsFramework/SkillsManager.luau) call this SAME function, each
-- with its own CombatLoadoutSnapshot (mirror vs. authoritative). Do not reimplement this logic
-- per side -- that is the exact drift trap 2 in the Phase C handoff brief warns about: two
-- implementations of "is this weapon valid" will disagree eventually, and the symptom is a client
-- that lets a player press a key the server then refuses.
--
-- Shared code cannot require server code, so the loadout is always passed in by the caller rather
-- than fetched here (trap 2).
--
-- This module answers LAYER 1 of D8 only ("can this skill be used at all"). LAYER 2 ("how does it
-- execute") is BasicAttackProfileRegistry's job and is never consulted here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemTypes = require(ReplicatedStorage.Shared.items.ItemTypes)
local SkillRequirementTypes = require(script.Parent.SkillRequirementTypes)

type WeaponRequirement = SkillRequirementTypes.WeaponRequirement

local SkillRequirementResolver = {}

local function hasTag(tags: { ItemTypes.ItemTag }?, wanted: string): boolean
	if not tags then
		return false
	end
	for _, tag in ipairs(tags) do
		if tag == wanted then
			return true
		end
	end
	return false
end

-- Returns (ok, reason). `reason` is only meaningful when `ok` is false.
local function weaponSatisfies(weapon: ItemTypes.CombatLoadoutWeapon, requirement: WeaponRequirement): (boolean, string?)
	local classes = requirement.classes
	if classes and #classes > 0 then
		local matched = false
		for _, class in ipairs(classes) do
			if weapon.weaponClass == class then
				matched = true
				break
			end
		end
		if not matched then
			return false, "wrong_weapon_class"
		end
	end

	local tags = requirement.tags
	if tags and #tags > 0 then
		for _, tag in ipairs(tags) do
			if not hasTag(weapon.tags, tag) then
				return false, "wrong_weapon_tags"
			end
		end
	end

	return true, nil
end

-- `offhandType` is an independent condition (e.g. "requires a shield"): when set it is checked on
-- its own, regardless of `mode`/`classes`/`tags`.
local function evaluateOffhand(
	requirement: WeaponRequirement,
	loadout: ItemTypes.CombatLoadoutSnapshot?
): (boolean, string?)
	local secondary = loadout and loadout.secondary
	local offhand = secondary and secondary.kind == "offhand" and secondary.offhand or nil
	if offhand and offhand.offhandType == requirement.offhandType then
		return true, nil
	end
	if requirement.offhandType == "shield" then
		return false, "requires_shield"
	end
	return false, "offhand_blocked"
end

-- LAYER 1 of D8: eligibility only. `requirement == nil` means the skill declared no weapon
-- requirement at all -- unrestricted, matching every skill's behavior before Phase C (additive
-- design, same precedent as `adaptiveBasicAttack` on SkillSpecBase in Phase B).
function SkillRequirementResolver.evaluate(
	requirement: WeaponRequirement?,
	loadout: ItemTypes.CombatLoadoutSnapshot?
): (boolean, string?)
	if not requirement then
		return true, nil
	end

	local mode = requirement.mode

	-- D8/trap 3: adaptive must NEVER reject -- resolution already falls back to unarmed_basic, so
	-- a rejection here would make BasicAttack unusable while unarmed (a total loss of basic
	-- offense). "optional" carries the same gating contract: the weapon can enhance the skill but
	-- is never required.
	if mode == "adaptive" or mode == "optional" then
		return true, nil
	end

	if requirement.offhandType then
		return evaluateOffhand(requirement, loadout)
	end

	local main = loadout and loadout.main
	local secondary = loadout and loadout.secondary
	local secondaryWeapon = secondary and secondary.kind == "weapon" and secondary.weapon or nil

	if mode == "any" then
		if not main and not secondaryWeapon then
			if requirement.allowUnarmed then
				return true, nil
			end
			return false, "requires_weapon"
		end
		local firstReason: string? = nil
		if main then
			local ok, reason = weaponSatisfies(main, requirement)
			if ok then
				return true, nil
			end
			firstReason = reason
		end
		if secondaryWeapon then
			local ok, reason = weaponSatisfies(secondaryWeapon, requirement)
			if ok then
				return true, nil
			end
			firstReason = firstReason or reason
		end
		return false, firstReason or "requirements_not_met"
	elseif mode == "main" then
		if not main then
			if requirement.allowUnarmed then
				return true, nil
			end
			return false, "requires_weapon"
		end
		return weaponSatisfies(main, requirement)
	elseif mode == "secondary" then
		if not secondaryWeapon then
			if requirement.allowUnarmed then
				return true, nil
			end
			return false, "requires_weapon"
		end
		return weaponSatisfies(secondaryWeapon, requirement)
	elseif mode == "both" then
		if not main or not secondaryWeapon then
			if requirement.allowUnarmed and not main and not secondaryWeapon then
				return true, nil
			end
			return false, "requires_weapon"
		end
		local mainOk, mainReason = weaponSatisfies(main, requirement)
		if not mainOk then
			return false, mainReason
		end
		local secOk, secReason = weaponSatisfies(secondaryWeapon, requirement)
		if not secOk then
			return false, secReason
		end
		return true, nil
	end

	return false, "requirements_not_met"
end

return SkillRequirementResolver
