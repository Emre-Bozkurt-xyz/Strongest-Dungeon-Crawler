--!strict
-- Dummy NPC Character Spec - Training dummy for testing

local Types = require(script.Parent.Parent.Types)

local Dummy: Types.CharacterSpec = {
	id = "Dummy",
	displayName = "Training Dummy",

	-- Visual assets
	model = nil, -- Uses model from Workspace/NPCs/Dummy
	animations = {
		-- Attack animations (used by NPCAnimationController)
		attack = {
			default = { "rbxassetid://122752973149294" },
			-- bySkill and byCategory can be added when needed:
			-- bySkill = { Punch = { "rbxassetid://..." } },
			-- byCategory = { melee_light = { "rbxassetid://..." } },
		},

		-- Hit reactions
		hit_light = nil, -- TODO: Add animation ID when available
		hit_heavy = nil,
		stagger = { "rbxassetid://107074060892127", "rbxassetid://111597840737018" },

		-- Death
		death = nil,
		revive = nil,
	},

	-- Stagger rules (training dummy is easier to stagger)
	stagger = {
		threshold = 1, -- 1 damage triggers stagger (lower than player)
		duration = 1.5, -- 1.5 second stagger
		cooldown = 1.0, -- Can be staggered every 1 second
		maxStackDamage = 100, -- Guaranteed stagger at 100+ damage
		canInterruptSkills = true,
	},

	-- Audio
	sounds = {
		hit = {
			-- TODO: Add dummy hit sounds (wood/metal impact)
		},
		death = {
			-- TODO: Add destruction sound
		},
	},

	-- Metadata
	tags = { "humanoid", "training", "npc" },
}

return Dummy
