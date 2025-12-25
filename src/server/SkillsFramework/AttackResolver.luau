--!strict
-- AttackResolver: Unified resolver for attack composition queries
-- Builds attack packets from base damage values and applies modifiers
-- Integrates with ModifierRegistry for dynamic transformations

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared

local AttackTypes = require(Shared.skills.AttackTypes)
local ModifierRegistry = require(script.Parent.ModifierRegistry)

type AttackPacket = AttackTypes.AttackPacket

-- Type definitions (inline until proper type module exists)
type AttackQueryContext = {
	entityId: string,
	skillId: string,
	queryType: string,
	tags: { string }?,
	step: number?,
	metadata: { [string]: any }?,
	baseAttack: {
		damage: number?,
		damageType: string?,
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

	if baseAttack.damage and baseAttack.damage > 0 then
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
