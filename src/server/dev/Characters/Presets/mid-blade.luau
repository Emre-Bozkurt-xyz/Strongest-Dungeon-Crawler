--!strict
-- A sword-and-board character a few hours in: Blade attuned and deep into Weight (Momentum chosen),
-- Fire attuned for a Fire II infusion, a full first bar, and gear in three slots.
return {
	extends = "starter",
	level = 12,
	attributes = { Strength = 14, Dexterity = 8, Perception = 1, unspent = 3 },
	mastery = {
		Blade = { trunk = "mastered", a = { rank = 4 }, b = 250 },
		Fire = { trunk = 200 },
	},
	attuned = { "Blade", "Fire" },
	bar = { { "BasicAttack", "TripleStrike", "Dash", "DodgeRoll", "CascadingManaBalls" } },
	equipment = {
		Main = { "iron_sword", rarity = "magic", affixes = { "fury", "of_vigor" } },
		Secondary = { "round_shield", rarity = "magic" },
		Body = { "leather_chest", rarity = "normal" },
	},
	bag = {
		{ "mana_potion", 5 },
		{ "iron_dagger", rarity = "magic" },
		{ "crooked_wand", rarity = "normal" },
	},
	infusion = "fire.fire_2",
	passives = { "blade.momentum" },
	pools = { Health = 0.6 },
}
