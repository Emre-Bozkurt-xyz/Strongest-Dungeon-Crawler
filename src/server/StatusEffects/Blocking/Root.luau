--!strict
-- Root effect - Prevents movement but allows casting

return {
	id = "root",
	duration = 2.0, -- 2 second default root
	maxStacks = 1,
	stacking = "aggregate",
	durationPolicy = "refresh",
	blocksActions = {
		move = true,
		jump = true,
		dodge = true,
	},
	-- cast and interact are NOT blocked
	onApply = function(_target: string, _source: string?, _params: any?, _stacks: number)
		-- TODO: Root VFX
	end,
	onRemove = function(_target: string, _source: string?, _stacks: number)
		-- No cleanup needed
	end,
}
