--!strict
-- What a dev session gives a player on top of their save: the skills they own, and for a brand-new
-- save the starting items, attribute point and AttackSpeed base. Read by the session-start hook
-- (InitDev) and by the `starter` character preset, so the two cannot drift apart.
--
-- Items are written as character spec items (Characters/Types): an id, an optional stack count, and
-- an optional rarity.

local StarterKit = {}

StarterKit.skills = { "BasicAttack", "TripleStrike", "Dash", "DodgeRoll", "CascadingManaBalls" }

StarterKit.items = {
	{ "mana_potion", 5 },
	{ "iron_sword", rarity = "normal" },
	{ "iron_sword", rarity = "magic" },
	-- Two of each one-hander so dual-wield hand alternation can be exercised.
	{ "crooked_wand", rarity = "magic" },
	{ "crooked_wand", rarity = "normal" },
	{ "iron_dagger", rarity = "magic" },
	{ "iron_dagger", rarity = "normal" },
	{ "round_shield", rarity = "magic" },
	{ "leather_chest", rarity = "normal" },
}

-- Added to the attribute's base, once per save.
StarterKit.attributes = { Perception = 1 }

-- Base stat values set every session.
StarterKit.stats = { AttackSpeed = 1 }

return StarterKit
