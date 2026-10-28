-- Bleed: physical damage over time. Stacks independently, each with its own damage and timer, like
-- Burn: several cuts bleed together, and a stronger cut replaces the weakest at the cap.

return {
	id = "Bleed",
	isHarmful = true,
	duration = 4,
	maxStacks = 8,
	tickInterval = 0.5,
	stacking = "multi",
	durationPolicy = "independent",
	capPolicy = "refreshWeakest",
	potencyKeys = { "damagePerTick" },
	getPotency = function(params: any)
		return if params then (params.damagePerTick or 0) else 0
	end,
	onTick = function(target: string, source: string?, params: any?, _stacks: number, _dt: number, ctx: any)
		local amount = if params then (params.damagePerTick or 0) else 0
		if amount > 0 and ctx and ctx.applyAttack then
			local sourceId = source or ""
			ctx.applyAttack(target, {
				packets = { { type = "damage", damageType = "Physical", amount = amount } },
				sourceId = sourceId,
				metadata = { effectId = "Bleed", isCrit = false },
			}, sourceId)
		end
	end,
}
