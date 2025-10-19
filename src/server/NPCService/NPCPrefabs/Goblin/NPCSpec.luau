--!strict
-- Goblin NPC specification (server-only)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StatTypes = require(ReplicatedStorage.Shared.StatTypes)
local BehaviorToolkit = require(script.Parent.Parent.Parent.BehaviorToolkit)

return {
	animations = {
		attack = {
			default = { "rbxassetid://GOBLIN_DEFAULT_ATTACK" },
			bySkill = {
				-- Example: Punch = { "rbxassetid://GOBLIN_PUNCH_A", "rbxassetid://GOBLIN_PUNCH_B" },
			},
			byCategory = {
				melee_light = { "rbxassetid://GOBLIN_LIGHT_A", "rbxassetid://GOBLIN_LIGHT_B" },
				melee_combo = { "rbxassetid://GOBLIN_COMBO" },
			},
		}
    },
	movement = {
		walkSpeed = 10,
		runSpeed = 16,
		patrolRadius = 18,
		jumpHeight = 7.2,
		canJump = true,
	},
	combat = {
		damage = 12,
		attackRange = 6,
		attackCooldown = 1.4,
		aggroRange = 24,
		skills = { "Punch" },
		attackPattern = "basic",
	},
	behavior = BehaviorToolkit.Defaults.basic({
		thinkInterval = 0.25,
		enablePatrol = true,
		leashRadius = 28,
		maxChaseDistance = 48,
		repathDistance = 5,
		repathInterval = 0.6,
		idleHoldMin = 1,
		idleHoldMax = 3,
		fleeHealthThreshold = 0.2,
		resumeHealthThreshold = 0.5,
	}),
	damageable = {
		configure = function(stats)
			local healthPool = stats[StatTypes.PoolStats.Health]
			if healthPool and healthPool.setBaseValue then
				healthPool:setBaseValue(220)
			end

			local physicalDamage = stats[StatTypes.StaticStats.PhysicalDamage]
			if physicalDamage and physicalDamage.setBaseValue then
				physicalDamage:setBaseValue(18)
			end
		end,
	},
}
