--!strict
-- Training dummies near the world spawn, each kept under a different set of ailments, for checking
-- the status marks under enemy health bars. Ailments are put back before they run out, so the marks
-- stay up for as long as the scenario is loaded.

local AILMENTS: { { effects: { { id: string, params: { [string]: any }? } } } } = {
	{ effects = { { id = "Burn", params = { damagePerTick = 1 } } } },
	{ effects = { { id = "Chill" }, { id = "Slow" } } },
	{ effects = { { id = "Bleed", params = { damagePerTick = 1 } }, { id = "Sunder" } } },
}

local REAPPLY_EVERY = 1.5

return {
	title = "Status marks",
	description = "Three dummies with ailments (burn; chill and slow; bleed and sunder), for checking the marks under health bars.",
	setup = function(s)
		local row = CFrame.lookAt(Vector3.new(-9, 0, -22), Vector3.new(-9, 0, 1))
		local dummies = s.spawnRow("Dummy", #AILMENTS, row, { spacing = 8 })
		local function apply()
			for index, dummy in ipairs(dummies) do
				for _, effect in ipairs(AILMENTS[index].effects) do
					s.status(dummy, effect.id, effect.params)
				end
			end
		end
		apply()
		s.every(REAPPLY_EVERY, apply)
	end,
}
