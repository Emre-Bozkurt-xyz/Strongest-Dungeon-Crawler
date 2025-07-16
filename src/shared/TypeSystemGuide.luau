--[[
STAT SYSTEM TYPE GUIDE
=====================

This guide explains the type system for the player stats in a C#-like way.

=====================================
1. CENTRALIZED TYPE SYSTEM
=====================================

All types are now defined in ONE place: StatTypes.luau
This is like having a C# namespace with all your enums and types.

Instead of scattered type definitions, everything comes from:
local Types = require(script.Parent.StatTypes)

=====================================
2. TYPE CATEGORIES
=====================================

STRING LITERAL TYPES (Your "Enums"):
- StaticStatType: "PhysicalDamage" | "MagicDamage" | etc.
- PoolType: "Health" | "Mana" | "Stamina" | "ManaShield" 
- StatType: StaticStatType | PoolType (all stat names)

CLASS INSTANCE TYPES:
- StatClass: For calculated stats (damage, crit chance)
- PoolStatClass: For pool stats (health, mana with current/max)
- PlayerStats: Collection holding all stat instances

CONFIGURATION TYPES:
- StatConfig: For creating StatClass instances
- PoolConfig: For creating PoolStatClass instances  
- ModifierConfig: For creating stat modifiers
- PoolReservation: For reserving pool amounts

=====================================
3. HOW TO USE THE TYPES
=====================================

INSTEAD OF HARDCODING STRINGS:
❌ Bad:
StatsManager.addModifier(player, "Health", modifier)
StatsManager.addModifier(player, "PhysicalDamage", modifier)

✅ Good (using enum-like constants):
StatsManager.addModifier(player, Types.PoolStats.Health, modifier)
StatsManager.addModifier(player, Types.StaticStats.PhysicalDamage, modifier)

FUNCTION PARAMETERS WITH TYPE SAFETY:
function addModifier(player: Player, statName: StatType, modifier)
-- This ensures only valid stat names can be passed

TYPE CHECKING:
local stat = StatsManager.getStat(player, Types.PoolStats.Health)
if StatTypeUtil.isPoolStat(stat) then
    -- TypeScript-style type narrowing
    print("Current:", stat:getCurrentValue())
    print("Max:", stat:getMaxValue())
else
    print("Value:", stat:getValue())
end

ITERATING OVER ALL STATS:
for _, statName in pairs(Types.AllStatNames) do
    local stat = StatsManager.getStat(player, statName)
    -- Process each stat
end

=====================================
4. IMPORT PATTERN
=====================================

In any file that needs stat types:

local Types = require(game.ReplicatedStorage.Shared.StatTypes)
local StatTypeUtil = require(game.ReplicatedStorage.Shared.StatTypeUtil)

-- Import the types you need
type StatType = Types.StatType
type PlayerStats = Types.PlayerStats

-- Use the enum-like constants
local healthStat = Stats[Types.PoolStats.Health]
local damageStat = Stats[Types.StaticStats.PhysicalDamage]

=====================================
5. BENEFITS (C#-like Experience)
=====================================

✅ Single source of truth (like C# namespace)
✅ Intellisense/autocomplete for stat names
✅ Compile-time errors for invalid stat names
✅ Easy refactoring (rename in one place)
✅ Type-safe function parameters
✅ Clear separation of concerns

=====================================
6. FILE PURPOSES
=====================================

StatTypes.luau:
- Central type definitions (like C# namespace)
- Enum-like constants
- No logic, just types and constants

StatTypeUtil.luau:  
- Utility functions for working with types
- Type checking functions (isPoolStat, etc.)
- Helper functions

StatsConfig.luau:
- Configuration data for default stats
- Factory function for creating default stats
- Re-exports main types for convenience

StatsManager.luau:
- Business logic for managing player stats
- Uses types from StatTypes.luau
- Type-safe function parameters

=====================================
7. MIGRATION EXAMPLE
=====================================

OLD WAY (scattered types, hardcoded strings):
```luau
-- In multiple files:
export type PoolType = "Health" | "Mana"...
StatsManager.addModifier(player, "Health", modifier)
if statName == "Health" then...
```

NEW WAY (centralized, type-safe):
```luau
-- In all files:
local Types = require(...StatTypes)
StatsManager.addModifier(player, Types.PoolStats.Health, modifier)  
if statName == Types.PoolStats.Health then...
```

This gives you the C# experience you want:
- Strong typing
- Intellisense
- Compile-time safety
- Easy refactoring
- Clear organization
]]

return {} -- Empty module, just documentation
