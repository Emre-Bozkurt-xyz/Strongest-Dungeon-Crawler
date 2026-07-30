--!strict
-- Deterministic hand-candidate resolution for adaptive dual-wield BasicAttack steps (Phase C,
-- D9 in docs/tasks/equipment-item-architecture.md).
--
-- An authored `hand` on a profile step always wins (Guardrail 6: explicit over inferred). Only
-- steps that leave `hand` unset ask this resolver to decide, and only then does alternation ever
-- happen. Alternation is pure/stateless from this module's point of view: callers own an
-- AlternationState cursor and pass it in/out so it can be reset at the right times.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemTypes = require(ReplicatedStorage.Shared.items.ItemTypes)
local BasicAttackProfileTypes = require(script.Parent.BasicAttackProfileTypes)

type BasicAttackHand = BasicAttackProfileTypes.BasicAttackHand

local HandResolver = {}

export type AlternatingHand = "main" | "secondary"

export type AlternationState = {
	nextHand: AlternatingHand,
}

-- D9: alternation always restarts on main at the beginning of a combo. Callers reset this whenever
-- a new combo chain begins. In practice that single reset point also covers trap 4's "reset on
-- weapon swap, death, respawn": a fresh combo chain is exactly what starting to attack again after
-- any of those produces, so there is no separate stale-cursor case to handle -- resolveHand below
-- also re-checks the live loadout on every call rather than trusting the cursor blindly (see
-- hasValidOneHandedWeapon), so a cursor pointing at a hand that no longer holds a weapon is never
-- acted on as if it still did.
function HandResolver.newAlternationState(): AlternationState
	return { nextHand = "main" }
end

local function hasValidOneHandedWeapon(loadout: ItemTypes.CombatLoadoutSnapshot?, hand: AlternatingHand): boolean
	if not loadout then
		return false
	end
	if hand == "main" then
		local main = loadout.main
		return main ~= nil and main.handedness == "one_handed"
	end
	local secondary = loadout.secondary
	if not secondary or secondary.kind ~= "weapon" or not secondary.weapon then
		return false
	end
	return secondary.weapon.handedness == "one_handed"
end

-- Resolve which hand a step should use.
--
-- 1. An authored hand on the step always wins -- returned as-is, alternation state untouched.
-- 2. Otherwise: when both hands currently hold a valid one-handed weapon, alternate (consumes and
--    advances `state`). The same input always produces the same hand sequence (Guardrail 9).
-- 3. Otherwise: use whichever single hand actually holds a valid one-handed weapon (main
--    preferred), falling back to "main" so BaseSkill:resolveWeaponDamage's own unarmed fallback
--    still applies when neither hand holds anything.
function HandResolver.resolveHand(
	stepHand: BasicAttackHand?,
	loadout: ItemTypes.CombatLoadoutSnapshot?,
	state: AlternationState
): BasicAttackHand
	if stepHand ~= nil then
		return stepHand
	end

	local mainValid = hasValidOneHandedWeapon(loadout, "main")
	local secondaryValid = hasValidOneHandedWeapon(loadout, "secondary")

	if mainValid and secondaryValid then
		local hand = state.nextHand
		state.nextHand = if hand == "main" then "secondary" else "main"
		return hand
	end

	if secondaryValid and not mainValid then
		return "secondary"
	end

	return "main"
end

return HandResolver
