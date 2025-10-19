--!strict
local data = {
    name = "TripleStrike",
    description = "Three quick strikes in different arcs",
    cooldown = 6.0,
    gcd = 1.0,
    level = 1,
    animCategory = "melee_combo",
    hits = {
        { t = 0.10, yaw = 0, coneAngle = 50, coneRange = 8, playersOnly = true, damageMult = 0.8 },
        { t = 0.25, yaw = -25, coneAngle = 50, coneRange = 8, playersOnly = true, damageMult = 1.0 },
        { t = 0.40, yaw = 25, coneAngle = 50, coneRange = 8, playersOnly = true, damageMult = 1.2 },
    },
}
return data
