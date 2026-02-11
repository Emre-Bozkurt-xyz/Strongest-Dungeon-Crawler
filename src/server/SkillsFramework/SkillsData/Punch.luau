--!strict
local StatTypes = require(game:GetService("ReplicatedStorage").Shared.StatTypes)
local Types = require(game:GetService("ReplicatedStorage").Shared.skills.SkillSpecTypes)

local data: Types.ServerSkillConfig = {
	name = "Punch",
	tags = { "melee", "light" },
	description = "A simple melee attack",
	cooldown = 2.0,
	gcd = 1.0,
	level = 1,
	animCategory = "melee_light",
	combo = {
		steps = 3,
		window = 0.6,
		stepDelays = { 0.1, 0.1, 1.5 },
		hitDelays = { 0.32, 0.27, 0.35 },
		stepDurations = { 0.45, 0.4, 0.5 },
	},
	costs = { 10, 12, 15 },
	baseResource = StatTypes.PoolStats.Stamina,
}
return data
