--!strict
-- Default Character Spec for Player Characters

local Types = require(script.Parent.Types)

local PlayerCharacter: Types.CharacterSpec = {
	id = "PlayerCharacter",
	displayName = "Player",

	-- Visual assets
	model = nil, -- Uses player's character model
	animations = {
		-- Hit reactions
		stagger = { "rbxassetid://107074060892127", "rbxassetid://111597840737018" },

		-- Death
		death = nil,
		revive = nil,

		-- Movement (default humanoid animations used if nil)
		idle = nil,
		walk = nil,
		run = nil,
		jump = nil,
		fall = nil,
	},

	-- Stagger rules
	stagger = {
		threshold = 1, -- 50 damage triggers stagger
		duration = 1.5, -- 1.5 second stagger (matches Stagger status effect)
		cooldown = 1.0, -- Can't be staggered more than once per 1 second
		maxStackDamage = 150, -- Guaranteed stagger if hit for 150+ damage
		canInterruptSkills = true, -- Stagger cancels active skills
	},

	-- Audio
	sounds = {
		hit = {
			-- TODO: Add hit sound IDs
			-- "rbxassetid://1234567890",
		},
		death = {
			-- TODO: Add death sound IDs
		},
	},

	-- Metadata
	tags = { "humanoid", "player" },
}

return PlayerCharacter
