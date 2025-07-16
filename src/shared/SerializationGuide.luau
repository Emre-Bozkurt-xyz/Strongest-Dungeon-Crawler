--[[
COMPREHENSIVE STAT SERIALIZATION SYSTEM
======================================

This document explains the enhanced serialization system that can fully 
reconstruct stat classes with all their state, including modifiers, 
reservations, and internal properties.

======================================
1. WHAT IS SERIALIZED
======================================

BASIC PROPERTIES:
✅ statType ("static" or "pool")
✅ name, description
✅ baseValue, minValue, maxValue

POOL-SPECIFIC PROPERTIES:
✅ currentValue
✅ reservations array (with all reservation data)

STATIC STAT PROPERTIES:
✅ All modifier effects are preserved

MODIFIERS (FULL STATE):
✅ value, type ("flat" or "percent")
✅ source_id, description
✅ isActive state
✅ modifierType (for proper class reconstruction)
✅ Special properties (e.g., targetStat for PercentOfStatModifier)

PERFORMANCE CACHE:
✅ _cachedValue, _cachedMaxValue
✅ _isDirty, _maxIsDirty flags

======================================
2. SERIALIZATION API
======================================

SERIALIZE STATS:
```luau
local serializedData = StatTypeUtil.serializeStats(playerStats)
```

DESERIALIZE STATS:
```luau
local restoredStats = StatTypeUtil.deserializeStats(serializedData)
```

The restored stats are FULLY FUNCTIONAL class instances with:
- All methods intact (getValue, addModifier, etc.)
- All modifiers working as before
- All reservations preserved
- Performance cache restored

======================================
3. SUPPORTED MODIFIER TYPES
======================================

StatModifier:
- Basic flat/percent modifiers
- Automatically reconstructed

PercentOfStatModifier:
- Cross-stat reference modifiers
- targetStat property preserved
- References restored after all stats exist

EXTENSIBLE DESIGN:
- Easy to add new modifier types
- Just add detection in _serializeModifiers
- Add reconstruction in deserializeStats

======================================
4. ROUND-TRIP GUARANTEES
======================================

PERFECT RECONSTRUCTION:
✅ serialize(deserialize(data)) == original functionality
✅ All modifier calculations work identically
✅ All cross-references (PercentOfStat) preserved
✅ Performance characteristics maintained

DATA INTEGRITY:
✅ No loss of precision in numeric values
✅ All string/boolean properties preserved
✅ Complex nested structures handled

======================================
5. USAGE PATTERNS
======================================

SAVE PLAYER DATA:
```luau
local playerStats = StatsManager.getAllStats(player)
local saveData = StatTypeUtil.serializeStats(playerStats)
-- Save to DataStore/Database
```

LOAD PLAYER DATA:
```luau
-- Load from DataStore/Database
local restoredStats = StatTypeUtil.deserializeStats(saveData)
-- Stats are now fully functional class instances
```

NETWORKING:
```luau
-- Server → Client
local serialized = StatTypeUtil.serializeStats(playerStats)
remoteEvent:FireClient(player, serialized)

-- Client receives and can use immediately
local stats = StatTypeUtil.deserializeStats(serialized)
```

======================================
6. PERFORMANCE CONSIDERATIONS
======================================

SERIALIZATION SIZE:
- Larger than simple value-only serialization
- Includes complete state for perfect reconstruction
- Example: ~3x size increase for complex stats

SERIALIZATION SPEED:
- Fast for typical player stat counts (10-20 stats)
- Scales linearly with number of modifiers
- Cache state preserved to avoid recalculation

DESERIALIZATION FEATURES:
- Two-pass reconstruction (stats first, then modifiers)
- Handles cross-references correctly
- Maintains all metatable/inheritance relationships

======================================
7. INTEGRATION WITH EXISTING SYSTEMS
======================================

STATSMANAGER:
- Already uses StatTypeUtil.serializeStats()
- Network events automatically use new format
- No changes needed to existing API

CLIENT SYSTEMS:
- Can receive and use deserialized stats immediately
- All stat methods work as expected
- UI can call getValue(), getBreakdown(), etc.

DATASTORE INTEGRATION:
```luau
-- Save
local success = pcall(function()
    local data = StatTypeUtil.serializeStats(playerStats)
    dataStore:SetAsync(player.UserId, data)
end)

-- Load
local success, data = pcall(function()
    return dataStore:GetAsync(player.UserId)
end)
if success and data then
    local restoredStats = StatTypeUtil.deserializeStats(data)
    -- Apply to player...
end
```

======================================
8. ERROR HANDLING
======================================

MISSING MODIFIER CLASSES:
- Falls back to StatModifier if unknown type
- Warns about missing modifier types
- Continues processing other modifiers

MALFORMED DATA:
- Uses safe defaults for missing properties
- Validates numeric ranges
- Preserves as much state as possible

CROSS-REFERENCE FAILURES:
- PercentOfStatModifier handles missing target stats
- Graceful degradation if references broken
- Continues functioning with available stats

======================================
9. EXTENSIBILITY
======================================

ADDING NEW MODIFIER TYPES:
1. Create modifier class with modifierType property
2. Add detection in StatTypeUtil._serializeModifiers
3. Add reconstruction in deserializeStats
4. Handle special properties as needed

ADDING NEW STAT TYPES:
1. Follow StatClass/PoolStatClass pattern
2. Add statType property for identification
3. Add serialization logic in serializeStats
4. Add reconstruction in deserializeStats

CUSTOM PROPERTIES:
- Easy to add new properties to serialization
- Maintain backward compatibility
- Use optional properties with defaults

======================================
10. TESTING & VALIDATION
======================================

ROUND-TRIP TESTING:
- SerializationExamples.demonstrateRoundTrip()
- Tests complex scenarios with multiple modifier types
- Validates all functionality after reconstruction

COMPARISON TESTING:
- SerializationExamples.compareSerializationSizes()
- Shows size impact vs benefits
- Demonstrates comprehensive state preservation

INTEGRATION TESTING:
- Use SerializationExamples for live testing
- Validates with real player data
- Tests save/load workflows

======================================
CONCLUSION
======================================

This comprehensive serialization system provides:
✅ Perfect state reconstruction
✅ Full compatibility with existing code
✅ Support for complex modifier relationships
✅ Performance optimization through cache preservation
✅ Extensible design for future stat types
✅ Robust error handling and graceful degradation

The system enables true "stateful" serialization where not just values
but the entire computational context is preserved and restored.
]]

return {} -- Documentation only
