--!strict
local data = {
    name = "Punch",
    description = "A simple melee attack",
    cooldown = 2.0,
    gcd = 1.0,
    level = 1,
    animCategory = "melee_light",
    combo = {
        steps = 3,
        window = 1,
        stepDelays = { 0.3, 0.4, 1 },
        hitDelays = { 0.4, 0.4, 0.4 },
    },
}
return data
