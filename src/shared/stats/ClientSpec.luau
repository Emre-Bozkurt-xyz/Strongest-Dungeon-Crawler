--!strict
-- Client-facing stats spec for UI (labels, descriptions, order, and formatting hints)
-- Safe to share with the client. No gameplay-critical values here.

local Types = require(script.Parent.Parent.StatTypes)

export type StatDisplay = {
	label: string,
	description: string?,
	group: "Pools" | "Offense" | "Recovery" | "Other"?,
	format: "int" | "percent" | "value" | "regen"?,
	order: number?,
}

local ClientSpec: { [Types.StatType]: StatDisplay } = {
	-- Pools
	Health = { label = "Health", description = "Health pool.", group = "Pools", format = "value", order = 10 },
	Mana = { label = "Mana", description = "Resource used for skills.", group = "Pools", format = "value", order = 20 },
	Stamina = { label = "Stamina", description = "Increases endurance and ability to act.", group = "Pools", format = "value", order = 30 },
	ManaShield = { label = "Mana Shield", description = "Absorbs damage using mana.", group = "Pools", format = "value", order = 40 },

	-- Offense
	PhysicalDamage = {
		label = "Physical Damage",
		description = "Damage from physical attacks.",
		group = "Offense",
		format = "int",
		order = 110,
	},
	MagicDamage = {
		label = "Magic Damage",
		description = "Damage from magical attacks.",
		group = "Offense",
		format = "int",
		order = 120,
	},
	CriticalHitChance = {
		label = "Crit Chance",
		description = "Chance to land a critical hit.",
		group = "Offense",
		format = "percent",
		order = 130,
	},
	CriticalHitDamage = {
		label = "Crit Damage",
		description = "Damage multiplier on critical hits.",
		group = "Offense",
		format = "percent",
		order = 140,
	},

	-- Recovery
	HealthRegeneration = {
		label = "Health Regen",
		description = "Health recovered per second.",
		group = "Recovery",
		format = "regen",
		order = 210,
	},
	ManaRegeneration = {
		label = "Mana Regen",
		description = "Mana recovered per second.",
		group = "Recovery",
		format = "regen",
		order = 220,
	},
	StaminaRegeneration = {
		label = "Stamina Regen",
		description = "Stamina recovered per second.",
		group = "Recovery",
		format = "regen",
		order = 230,
	},
}

-- Helper utilities
local StatsClientSpec = {}

function StatsClientSpec.get(specName: Types.StatType): StatDisplay?
	return ClientSpec[specName]
end

function StatsClientSpec.all(): { [Types.StatType]: StatDisplay }
	return ClientSpec
end

-- Return for direct table access as well
return setmetatable(StatsClientSpec, { __index = ClientSpec })
