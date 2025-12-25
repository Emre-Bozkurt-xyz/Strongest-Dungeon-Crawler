--!strict
-- Silence effect - Prevents casting but allows movement

return {
	id = "silence",
	duration = 4.0, -- 4 second default silence
	maxStacks = 1,
	stacking = "aggregate",
	durationPolicy = "refresh",
	blocksActions = {
		cast = true,
	},
	-- move, jump, dodge, interact are NOT blocked
	onApply = function(_target: string, _source: string?, _params: any?, _stacks: number)
		-- TODO: Silence VFX
	end,
	onRemove = function(_target: string, _source: string?, _stacks: number)
		-- No cleanup needed
	end,
}
