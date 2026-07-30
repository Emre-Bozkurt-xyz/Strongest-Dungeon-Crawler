--!strict
local Types = require(game:GetService("ReplicatedStorage").Shared.skills.SkillSpecTypes)

local data: Types.ServerSkillConfig = {
    name = "TripleStrike",
    tags = {"melee", "light"},
    description = "Three quick strikes in different arcs",
    cooldown = 6.0,
    gcd = 1.0,
    level = 1,
    animCategory = "melee_combo",
    cost = 20,
    hits = {
        { t = 0.10, yaw = 0, coneAngle = 50, coneRange = 8, damageMult = 1.2 },
        { t = 0.25, yaw = -25, coneAngle = 50, coneRange = 8, damageMult = 0.9 },
        { t = 0.40, yaw = 25, coneAngle = 50, coneRange = 8, damageMult = 0.9 },
    },
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
