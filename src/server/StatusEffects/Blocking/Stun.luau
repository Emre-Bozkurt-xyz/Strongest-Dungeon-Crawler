--!strict
-- Stun effect - Longer disabling effect that blocks all actions

return {
	id = "stun",
	duration = 3.0, -- 3 second default stun
	maxStacks = 1,
	stacking = "aggregate",
	durationPolicy = "refresh",
	blocksActions = {
		cast = true,
		move = true,
		jump = true,
		dodge = true,
		interact = true,
	},
	onApply = function(_target: string, _source: string?, _params: any?, _stacks: number)
		-- TODO: Play stun animation/VFX
		-- TODO: Emit to client
	end,
	onRemove = function(_target: string, _source: string?, _stacks: number)
		-- No cleanup needed
	end,
}
