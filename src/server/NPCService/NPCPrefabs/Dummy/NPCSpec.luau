--!strict
-- Dummy NPC specification (server-only behavior/stats)
-- Visual assets (animations, sounds) live in shared/Characters/NPCs/Dummy.luau
--
-- A training dummy: it stands where it is spawned and takes hits. It never moves, targets or
-- attacks, so a player can practise at any range their reach allows; something that fights back
-- is a different NPC. Its health regenerates so it is ready again shortly after a session.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StatTypes = require(ReplicatedStorage.Shared.StatTypes)
local BehaviorToolkit = require(script.Parent.Parent.Parent.BehaviorToolkit)

return {
	movement = {
		walkSpeed = 10,
		runSpeed = 16,
		patrolRadius = 0,
		jumpHeight = 7.2,
		canJump = false,
	},
	combat = {
		-- No skills and no aggro range: it never acquires a target, so it never attacks.
		damage = 0,
		attackRange = 0,
		attackCooldown = 1.4,
		aggroRange = 0,
		skills = {},
		attackPattern = "basic",
	},
	behavior = BehaviorToolkit.Defaults.basic({
		thinkInterval = 0.25,
		enablePatrol = false,
		leashRadius = 28,
		maxChaseDistance = 48,
		repathDistance = 5,
		repathInterval = 0.6,
		idleHoldMin = 1,
		idleHoldMax = 3,
		fleeHealthThreshold = 0,
		resumeHealthThreshold = 0,
	}),
	-- Hits teach only the flat training amount, and only while a mastery is below the training cap.
	progression = { training = true },
	damageable = {
		configure = function(stats)
			local healthPool = stats[StatTypes.PoolStats.Health]
			if healthPool and healthPool.setBaseValue and healthPool.fillToMax then
				healthPool:setBaseValue(220)
				healthPool:fillToMax()
			end

			local healthRegen = stats[StatTypes.StaticStats.HealthRegeneration]
			if healthRegen and healthRegen.setBaseValue then
				healthRegen:setBaseValue(20)
			end
		end,
	},
}
