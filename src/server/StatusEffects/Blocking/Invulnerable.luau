--!strict
-- Invulnerable effect - Blocks incoming damage without restricting actions

return {
	id = "invulnerable",
	isHarmful = false,
	duration = 0.3,
	maxStacks = 1,
	stacking = "aggregate",
	durationPolicy = "refresh",
	blocksActions = {
		damage = true,
	},
	onApply = function(_target: string, _source: string?, _params: any?, _stacks: number)
		-- No-op: damage blocking handled in CombatService
	end,
	onRemove = function(_target: string, _source: string?, _stacks: number)
		-- No cleanup needed
	end,
}
