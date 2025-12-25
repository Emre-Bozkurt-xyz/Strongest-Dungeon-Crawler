--!strict

-- Server-side mediator for skill-related stat/behavior queries.
-- This is an initial stub wired for incremental adoption starting with cost resolution.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SkillQueryTypes = require(ReplicatedStorage.Shared.skills.SkillQueryTypes)
local SkillModifierRegistry = require(script.Parent.SkillModifierRegistry)

type SkillQueryContext = SkillQueryTypes.SkillQueryContext
type SkillQueryResult = SkillQueryTypes.SkillQueryResult

local SkillMediator = {}

function SkillMediator.resolve(ctx: SkillQueryContext): SkillQueryResult
	local values: { [string]: any } = table.clone(ctx.base)
	local result: SkillQueryResult = {
		values = values,
		log = nil,
	}
	local modifiers = SkillModifierRegistry.getModifiers(ctx.entityId, ctx.event)
	for _, mod in ipairs(modifiers) do
		if mod.matches(ctx) then
			mod.apply(ctx, result)
		end
	end
	return result
end

return SkillMediator
