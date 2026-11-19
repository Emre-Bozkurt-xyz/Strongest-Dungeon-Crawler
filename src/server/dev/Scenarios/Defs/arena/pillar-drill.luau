--!strict
-- ExampleArena as a sword-and-board fight: the mid-blade character, the stage's own dummies and
-- slime (from its spawn markers), a slime at every pillar that comes back five seconds after it dies,
-- and a pair in the centre. Hitboxes are drawn and the camera sits a little further back for the
-- duration.

local Scenarios = require(script:FindFirstAncestor("Scenarios"))

return Scenarios.define({
	title = "Pillar drill",
	description = "Mid-blade in ExampleArena against respawning slimes at the pillars and a pair in the centre.",
	stage = "ExampleArena",
	character = "mid-blade",
	flags = { hitboxes = true },
	clientFlags = { inputFlow = false },
	tune = { ["Camera.baseline.shoulderBack"] = 8 },
	setup = function(s)
		for _, pillar in ipairs(s.markers("Pillar")) do
			s.spawn("Slime", pillar, { respawnDelay = 5 })
		end
		s.spawnRow("Slime", 2, "Center", { spacing = 6 })
	end,
})
