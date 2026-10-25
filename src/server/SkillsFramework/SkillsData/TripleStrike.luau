--!strict
local Types = require(game:GetService("ReplicatedStorage").Shared.skills.SkillSpecTypes)
local TripleStrikeSpec = require(game:GetService("ReplicatedStorage").Shared.skills.Specs.TripleStrike)

local data: Types.ServerSkillConfig = {
    name = "TripleStrike",
    tags = {"melee", "light"},
    description = "Three quick strikes in different arcs",
    cooldown = 6.0,
    gcd = 1.0,
    level = 1,
    animCategory = "melee_combo",
    cost = 20,
    hits = TripleStrikeSpec.hits,
    -- Phase C (D8): a dedicated sword combo -- requires a sword-class weapon in either hand.
    -- Demonstrates the "wrong_weapon_class" rejection path (see Phase C exit criterion 3).
    requirements = {
        weapon = {
            mode = "any",
            classes = { "sword" },
            allowUnarmed = false,
        },
    },
}
return data
