--!strict
-- AttackResolver: Unified resolver for attack composition queries
-- Builds attack packets from base damage values and applies modifiers
-- Integrates with ModifierRegistry for dynamic transformations

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared

local AttackTypes = require(Shared.skills.AttackTypes)
local ModifierRegistry = require(script.Parent.ModifierRegistry)

type AttackPacket = AttackTypes.AttackPacket

-- A single typed damage contribution. Weapons can deal more than one damage type (a flame sword
-- rolls Physical and Fire), which the single `damage`/`damageType` pair below cannot express.
export type TypedDamage = {
	type: string,
	amount: number,
}

-- Type definitions (inline until proper type module exists)
type AttackQueryContext = {
	entityId: string,
	skillId: string,
	queryType: string,
	tags: { string }?,
	step: number?,
	metadata: { [string]: any }?,
	baseAttack: {
		-- Single-type form. Still the path every non-weapon skill uses; unchanged.
		damage: number?,
		damageType: string?,
		-- Multi-type form, used by weapon-driven attacks. When present and non-empty this takes
		-- precedence over `damage`/`damageType`; one packet is emitted per entry. Additive by
		-- design: callers that do not set it behave exactly as before.
		damages: { TypedDamage }?,
		effectId: string?,
		effectChance: number?,
		comboStep: number?,
		isCrit: boolean?,
	},
}

type AttackQueryResult = {
	packets: { AttackPacket },
	metadata: {
		isCrit: boolean?,
		comboStep: number?,
		[string]: any,
	}?,
}

local AttackResolver = {}

-- Resolve an attack query (builds attack composition from base values)
local function resolveAttack(ctx: AttackQueryContext): AttackQueryResult
	local baseAttack = ctx.baseAttack

	-- Start with a single damage packet from base values
	local packets: { AttackPacket } = {}

	local typedDamages = baseAttack.damages
	if typedDamages and #typedDamages > 0 then
		-- Multi-type form: one packet per typed contribution, so a weapon's own damage types
		-- survive into the packet list instead of being flattened to a single hardcoded type.
		for _, entry in ipairs(typedDamages) do
			if entry.amount > 0 then
				table.insert(packets, {
					type = "damage",
					damageType = entry.type,
					amount = entry.amount,
				})
			end
		end
	elseif baseAttack.damage and baseAttack.damage > 0 then
		local damageAmount = baseAttack.damage
		local damageType = baseAttack.damageType or "Physical"

		table.insert(packets, {
			type = "damage",
			damageType = damageType,
			amount = damageAmount,
		})
	end

	-- Add effect packet if specified
	if baseAttack.effectId then
		local chance = baseAttack.effectChance or 1.0

		table.insert(packets, {
			type = "effect",
			effectId = baseAttack.effectId,
			chance = chance,
			params = {},
		})
	end

	-- Build result
	local result: AttackQueryResult = {
		packets = packets :: any,
		metadata = {
			isCrit = baseAttack.isCrit or false,
			comboStep = baseAttack.comboStep,
		},
	}

	-- Apply modifiers from registry (transforms packets, adds/removes packets, etc.)
	ModifierRegistry.applyModifiers(ctx.entityId, "resolveAttack", ctx, result)

	return result
end

-- Main resolver entry point
function AttackResolver.resolve(ctx: AttackQueryContext): AttackQueryResult
	-- Route to appropriate resolver based on query type
	if ctx.queryType == "resolveAttack" then
		return resolveAttack(ctx)
	else
		error(`Unknown query type: {ctx.queryType}`)
	end
end

return AttackResolver
