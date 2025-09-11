--!strict
-- Central catalog of status effect definitions. Server-only.

-- Keep this module untyped to avoid cross-file type identity mismatches.
local defs = {} :: { [string]: any }

-- Burn (DoT) — per-source stacks, each with own params/duration; ticks every second
-- Recommended for cases where different skills contribute different power

defs.Burn = {
	id = "Burn",
	duration = 5,
	maxStacks = 5,
	tickInterval = 1,
	stacking = "multi",
	durationPolicy = "independent",
	capPolicy = "refreshWeakest",
	getPotency = function(params: any)
		if not params then
			return 0
		end
		local p = params :: any
		return (p.damagePerTick or p.power or 0)
	end,
	onTick = function(target: Instance, source: Player?, params: any?, _stacks: number, _dt: number, ctx: any)
		local power = 0
		if params then
			local p = params :: any
			power = (p.damagePerTick or p.power or 0)
		end
		local dmg = power -- per-entry tick uses its own params
		if ctx and ctx.applyDamage then
			ctx.applyDamage(target, dmg, source, {
				kind = "magic",
				element = "fire",
				critAllowed = false,
			})
		end
	end,
}

-- Poison (DoT) — aggregate with combined potency
-- Multiple applies contribute to a single tick using paramCombine (sum)

defs.Poison = {
	id = "Poison",
	duration = 6,
	maxStacks = 10,
	tickInterval = 1,
	stacking = "aggregate",
	durationPolicy = "refresh",
	capPolicy = "refreshOldest",
	paramCombine = function(list: { any })
		local total = 0
		for _, p in list do
			if p then
				local v = (p.dpt or p.damagePerTick or p.power or 0)
				total += v
			end
		end
		return { dpt = total }
	end,
	onTick = function(target: Instance, source: Player?, params: any?, _stacks: number, _dt: number, ctx: any)
		local dpt = 0
		if params then
			local p = params :: any
			dpt = p.dpt or 0
		end
		if dpt > 0 and ctx and ctx.applyDamage then
			ctx.applyDamage(target, dpt, source, {
				kind = "physical",
				element = "poison",
				critAllowed = false,
			})
		end
	end,
}

-- Frenzy — charges that decay independently, used as a buff counter (no ticking)

defs.Frenzy = {
	id = "Frenzy",
	duration = 6,
	maxStacks = 3,
	stacking = "charges",
	durationPolicy = "independent",
	capPolicy = "refreshOldest",
	-- onApply/onRemove can notify UI or recalc derived stats
}

return defs
