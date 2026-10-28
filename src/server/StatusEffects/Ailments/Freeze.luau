-- Freeze: frozen solid for a moment. Everything a stun blocks, and the body stops moving too
-- (a stun blocks moving by input; a frozen NPC also has its walk speed taken to zero).

local ServerScriptService = game:GetService("ServerScriptService")

local SpeedModifiers = require(ServerScriptService.Server.Movement.SpeedModifiers)
local Stun = require(script.Parent.Parent.Blocking.Stun)

local SOURCE = "status::Freeze"

return {
	id = "Freeze",
	isHarmful = true,
	duration = 1,
	maxStacks = 1,
	stacking = "aggregate",
	durationPolicy = "refresh",
	blocksActions = Stun.blocksActions,
	onApply = function(target: string, source: string?, params: any?, stacks: number)
		Stun.onApply(target, source, params, stacks)
		SpeedModifiers.set(target, SOURCE, 0)
	end,
	onRemove = function(target: string, _source: string?, _stacks: number)
		SpeedModifiers.clear(target, SOURCE)
	end,
}
