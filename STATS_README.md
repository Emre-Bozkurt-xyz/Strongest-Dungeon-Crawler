# Player Attributes System

A comprehensive player attributeistics management system for Roblox games using the Warp networking library.

## Features

- **Server-authoritative attributes** - All attribute modifications happen on the server for security
- **Real-time synchronization** - Changes are instantly reflected on the client
- **Flexible attribute system** - Support for base attributes and temporary bonuses
- **Equipment bonuses** - Easily apply/remove equipment modifiers
- **Type safety** - Full TypeScript-style type annotations for better code quality
- **Extensible design** - Easy to add new attributes or modify existing ones

## Available Attributes

- **Strength** - Increases physical damage and carrying capacity
- **Intelligence** - Increases mana pool and spell effectiveness  
- **Dexterity** - Increases attack speed and critical hit chance
- **Perception** - Increases accuracy and detection abilities
- **Vitality** - Increases health points and stamina
- **Luck** - Increases rare item drop rates and critical hit chance

## Architecture

### Files Structure

```
src/
├── shared/
│   └── AttributesConfig.luau          # Shared configuration and types
├── server/
│   ├── AttributesManager.luau         # Main server-side attributes management
│   ├── AttributesExamples.luau        # Example usage and demos
│   └── init.server.luau          # Server initialization
└── client/
    ├── AttributesClient.luau          # Client-side attributes handling and UI
    └── init.client.luau          # Client initialization
```

### Data Flow

1. **Server** modifies player attributes using `AttributesManager`
2. **Warp** automatically syncs changes to the relevant client(s)
3. **Client** receives updates and refreshes the UI display
4. **Client** can request attributes updates if needed

## Usage Examples

### Basic Attribute Modification

```lua
local AttributesManager = require(script.AttributesManager)

-- Add points to a attribute
AttributesManager.addToAttribute(player, "Strength", 5)

-- Set a attribute to a specific value
AttributesManager.setAttribute(player, "Intelligence", 25)

-- Get current attribute value
local strength = AttributesManager.getAttribute(player, "Strength")
```

### Equipment System

```lua
-- Apply equipment bonus
AttributesManager.applyEquipmentBonus(player, "Strength", 15)

-- Remove equipment bonus
AttributesManager.removeEquipmentBonus(player, "Strength")
```

### Character Classes

```lua
-- Reset attributes and apply class bonuses
AttributesManager.resetAttributes(player)

-- Warrior class
AttributesManager.addToAttribute(player, "Strength", 10)
AttributesManager.addToAttribute(player, "Vitality", 8)

-- Mage class  
AttributesManager.addToAttribute(player, "Intelligence", 12)
AttributesManager.addToAttribute(player, "Perception", 5)
```

### Combat Calculations

```lua
local strength = AttributesManager.getAttribute(player, "Strength") or 10
local dexterity = AttributesManager.getAttribute(player, "Dexterity") or 10

local baseDamage = strength * 2
local critChance = dexterity / 100

local damage = math.random() < critChance and baseDamage * 2 or baseDamage
```

## API Reference

### AttributesManager (Server)

#### Functions

- `setAttribute(player, attributeType, value, isBonus?)` - Set a attribute to a specific value
- `addToAttribute(player, attributeType, amount, isBonus?)` - Add to an existing attribute
- `getAttribute(player, attributeType)` - Get current attribute value  
- `getAllAttributes(player)` - Get all attributes for a player
- `resetAttributes(player)` - Reset all attributes to default values
- `applyEquipmentBonus(player, attributeType, amount)` - Apply equipment bonus
- `removeEquipmentBonus(player, attributeType)` - Remove equipment bonus

#### Types

- `AttributeType` - "Strength" | "Intelligence" | "Dexterity" | "Perception" | "Vitality" | "Luck"
- `AttributeData` - `{ current: number, base: number, bonus: number }`
- `PlayerAttributes` - `{ [AttributeType]: AttributeData }`

### AttributesClient (Client)

#### Functions

- `getCurrentAttributes()` - Get cached player attributes
- `getAttribute(attributeType)` - Get specific attribute value
- `requestAttributesUpdate()` - Request fresh attributes from server

## Configuration

### Default Attributes

Edit `AttributesConfig.DEFAULT_ATTRIBUTES` to change starting attribute values:

```lua
AttributesConfig.DEFAULT_ATTRIBUTES = {
    Strength = { current = 10, base = 10, bonus = 0 },
    Intelligence = { current = 10, base = 10, bonus = 0 },
    -- ... other attributes
}
```

### Attribute Limits

```lua
AttributesConfig.MIN_ATTRIBUTE_VALUE = 1
AttributesConfig.MAX_ATTRIBUTE_VALUE = 999
```

### Adding New Attributes

1. Add to `AttributeType` in `AttributesConfig.luau`
2. Add to `DEFAULT_ATTRIBUTES` table
3. Add description to `ATTRIBUTE_DESCRIPTIONS`

## Testing

The system includes keyboard shortcuts for testing:

- **F1** - Request attributes update from server
- **F2** - Print current attributes to console

A full demo runs automatically when a player joins, showcasing:
- Character creation
- Leveling up
- Equipment bonuses
- Combat calculations
- Temporary buffs

## Best Practices

1. **Always modify attributes on the server** - Never trust client input
2. **Use equipment bonuses for temporary effects** - Keep base attributes for permanent progression
3. **Validate attribute requirements** - Check prerequisites before allowing actions
4. **Cache attributes on client** - Avoid excessive server requests
5. **Use type annotations** - Leverage Luau's type system for better code quality

## Security Considerations

- All attribute modifications are server-authoritative
- Client cannot directly modify attributes
- Input validation on all server functions
- Rate limiting through Warp networking layer

## Performance Notes

- Attributes are synced only when changed, not continuously
- Client-side caching reduces network requests
- Warp handles efficient networking automatically
- Minimal memory footprint per player

## Extending the System

### Adding Derived Attributes

```lua
-- Calculate derived attributes from base attributes
local function calculateHealth(vitality: number): number
    return vitality * 10 + 100
end

local function calculateMana(intelligence: number): number
    return intelligence * 5 + 50
end
```

### Adding Attribute Modifiers

```lua
-- Percentage-based modifiers
local function applyPercentageBonus(baseAttribute: number, percentage: number): number
    return math.floor(baseAttribute * (1 + percentage / 100))
end
```

### Integration with Data Stores

```lua
-- Save/load attributes to DataStore
local function savePlayerAttributes(player: Player)
    local attributes = AttributesManager.getAllAttributes(player)
    -- Save to DataStore
end

local function loadPlayerAttributes(player: Player)
    -- Load from DataStore
    -- Apply loaded attributes
end
```

This system provides a solid foundation for any RPG-style game requiring player progression and attributeistics management!
