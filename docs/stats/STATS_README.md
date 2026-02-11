# Player Attributes System

A comprehensive player attributes management system for Roblox games using the custom dispatcher networking layer.

## Features

- **Server-authoritative attributes** - All attribute modifications happen on the server for security
- **Real-time synchronization** - Changes are instantly reflected on the client
- **Flexible attribute system** - Support for base attributes and temporary bonuses
- **Equipment bonuses** - Easily apply/remove equipment modifiers
- **Type safety** - Luau type annotations for better code quality
- **Extensible design** - Easy to add new attributes or modify existing ones
- **Dispatcher-based networking** - Per-service events/requests with delta-based updates

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
│   └── init.server.luau               # Server initialization
└── client/
    ├── AttributesClient.luau          # Client-side attributes handling and UI
    └── init.client.luau               # Client initialization
```

### Data Flow

1. **Server** modifies player attributes using `AttributesManager` (authoritative)
2. **Server → Client (dispatcher event)**: Deltas are sent via `AttributesDelta` to relevant client(s)
3. **Client** receives updates and refreshes the UI display
4. **Client → Server (dispatcher request)**: On spawn or when needed, the client requests a full sync via `AttributesRequest`. Clients spend points with `AttributesSpendPoint`.

### Networking (Dispatcher)

- Events
  - `AttributesDelta` (Server → Client): Sends attribute deltas, including optional `{ type = "full_sync", data = ... }` payloads for initial sync
- Requests
  - `AttributesRequest` (Client → Server): Returns serialized full attribute state
  - `AttributesSpendPoint` (Client → Server): Body `{ target = AttributeType }` to spend an attribute point

## Usage Examples

### Basic Attribute Modification

```lua
local AttributesManager = require(script.AttributesManager)

-- Add points to an attribute
AttributesManager.addToAttribute(player, "Strength", 5)

-- Set an attribute to a specific value
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

- `setAttribute(player, attributeType, value, isBonus?)` - Set an attribute to a specific value
- `addToAttribute(player, attributeType, amount, isBonus?)` - Add to an existing attribute
- `getAttribute(player, attributeType)` - Get current attribute value  
- `getAllAttributes(player)` - Get all attributes for a player
- `resetAttributes(player)` - Reset all attributes to default values
- `applyEquipmentBonus(player, attributeType, amount)` - Apply equipment bonus
- `removeEquipmentBonus(player, attributeType)` - Remove equipment bonus
- `spendAttributePoint(player, attributeType)` - Spend one available attribute point

#### Types

- `AttributeType` - "Strength" | "Intelligence" | "Dexterity" | "Perception" | "Vitality" | "Luck"
- `AttributeData` - `{ current: number, base: number, bonus: number }`
- `PlayerAttributes` - `{ [AttributeType]: AttributeData }`

### AttributesClient (Client)

#### Functions

- `getCurrentAttributes()` - Get cached player attributes
- `getAttribute(attributeType)` - Get specific attribute value
- `requestAttributesData()` - Request fresh attributes from server (full sync)
- `spendPoint(attributeType)` - Ask server to spend a point (via dispatcher request)

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

A quick demo runs automatically when a player joins, showcasing:
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
- Optional rate limiting via dispatcher middleware

## Performance Notes

- Attributes are synced only when changed, not continuously
- Client-side caching reduces network requests
- The dispatcher handles efficient networking and delta-based updates
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

This system provides a solid foundation for any RPG-style game requiring player progression and attributes management!
