--!strict
-- Dummy NPC Character Spec - Training dummy for testing

local Types = require(script.Parent.Parent.Types)

local Slime: Types.CharacterSpec = {
	id = "Slime",
	displayName = "Slime",

	-- Visual assets
	model = nil, -- Uses model from Workspace/NPCs/Slime
	animations = {
		-- Attack animations (used by NPCAnimationController)
		walk = { "rbxassetid://75858114076016" },

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
		cooldown = 0.3, -- Can be staggered every 0.3 seconds
		maxStackDamage = 100, -- Guaranteed stagger at 100+ damage
		canInterruptSkills = true,
	},

	-- Audio
	sounds = {
		hit = {
			-- TODO: Add slime hit sounds (squishy/gelatinous impact)
		},
		death = {
			-- TODO: Add slime death sound
		},
	},

	-- Metadata
	tags = { "humanoid", "training", "npc" },
}

return Slime
