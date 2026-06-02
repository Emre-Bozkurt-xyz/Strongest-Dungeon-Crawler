# Equipment + Item Architecture Refactor

## Goal
Build a production-friendly item and equipment system inspired by Path of Exile's loot model, but tuned for a Roblox dungeon crawler.

The target system should support:

- fixed-level base equipment
- rolled base modifiers from authored ranges
- modular affixes with item-level gated tiers
- simple, readable item modification later
- unique items that can break normal equipment rules
- clean separation between runtime item state, gameplay config, and visuals
- scalable content authoring without giant registry files

## Product Direction

The game should use a "PoE-lite" loot model.

What to keep from Path of Exile:

- base equipment has a fixed authored item level
- item level gates when a base can drop
- base stats roll within authored ranges
- affix tiers are gated by item level
- higher-level areas/enemies/bosses unlock higher-level bases and better affix tiers
- uniques can have predefined or special rules that do not need to obey normal class affixes

What to avoid:

- mandatory deep crafting to make gear usable
- opaque multi-step crafting chains
- heavy currency manipulation
- late-game progression that requires spreadsheet-level optimization

Recommended player loop:

`kill -> drop -> compare -> equip or salvage -> occasionally improve a good item`

Crafting/modification should be optional correction and polishing, not the primary way to make equipment functional.

## Core Design Decisions

1. Base equipment level is authored and fixed.
   - `equipment.itemLevel` is the base item's fixed level.
   - generated item instances copy that value into `meta.itemLevel`.
   - normal gameplay should not mutate `meta.itemLevel`.
   - loot tables use base item level to decide eligibility.

2. Instance state stores rolls, not design rules.
   - rolled base modifiers live in `meta.baseModifiers`.
   - rolled affixes live in `meta.affixes`.
   - display name can be cached in `meta.displayName`.

3. Affixes are modular content.
   - no giant single `AffixRegistry` content file.
   - affix modules live under prefix/suffix folders.
   - registry only autoloads, indexes, and exposes policy.

4. Visual profile separation is conditional, not dogma.
   - reusable or rig-specific visuals can remain separate profiles.
   - single-use visuals should eventually live beside the item in an item content package.
   - the registry should make both authoring styles possible.

5. Equipment visuals use purpose-based rig sockets.
   - profiles target `Weapon_Main`, `Armor_Chest`, etc.
   - raw body-part names remain temporary fallback only.

## Target Content Shape

Long-term content should move toward packages:

```text
items/
  Equipment/
    IronSword/
      init.luau
      visual.r6.luau
    LeatherChest/
      init.luau
      visual.r6.luau
  Affixes/
    Prefixes/
      Fury.luau
      Sentinel.luau
    Suffixes/
      OfVigor.luau
      OfTheFairy.luau
```

Current implementation supports this direction:

- equipment packages load from `src/shared/items/Equipment/<ItemName>/init.luau`
- package-local visuals load from `visual.*.luau` children
- flat `Defs/` remains available for non-equipment and legacy content
- flat `VisualProfiles/` remains available for shared/reusable visual profiles

## Static Item Identity

Each item definition should keep a small identity layer:

- `id`
- `name`
- `category`
- `icon`
- `stackLimit`
- `tags`
- optional static metadata that is truly static

Static item identity should not use the same type as runtime item instance metadata.

## Equipment Config

Equipment items declare an explicit `equipment` block:

- `itemLevel`
- `slots`
- `class`
- `affixContext`
- `requirements`
- `baseRolls`
- `capabilities`
- `visualProfileId`

This replaces the legacy loose fields:

- `equipSlots`
- `baseStats`
- top-level `requirements`
- top-level `visuals`

Those legacy fields should remain only during migration.

## Runtime Item Instance State

Item instances own generated state:

- `uid`
- `itemId`
- `stackSize`
- `meta.itemLevel`
- `meta.rarity`
- `meta.affixes`
- `meta.baseModifiers`
- `meta.displayName`
- consumable charges, durability, or other mutable state

For equipment, `meta.itemLevel` is copied from the base equipment's fixed `equipment.itemLevel` unless explicitly overridden by dev/test generation.

## Base Rolls

Base rolls are authored on the item base.

Example:

```luau
baseRolls = {
  {
    id = "base_roll::armor",
    kind = "flat",
    target = "Armor",
    min = 2,
    max = 4,
  },
}
```

Roll scaling should be simple and readable:

- either fixed `min/max`
- or controlled item-level scaling fields while the project is young
- avoid hidden formula chains until content volume demands them

## Affix Content Model

Affixes should be authored as content modules.

Each affix owns:

- `id`
- `kind`
- `weight`
- `tiers`
- tier labels
- tier item-level gates
- context-specific modifier rolls

Affix context should be explicit through `equipment.affixContext`, not inferred from tags or slots once migration is complete.

Recommended future folders:

- `src/shared/items/Affixes/Prefixes`
- `src/shared/items/Affixes/Suffixes`

The registry should:

- autoload affix modules
- validate ids/kinds/tiers
- index by kind
- expose rarity policy and affix budgets
- avoid owning individual affix content inline

## Rarity Policy

Rarity decides affix budget and broad item identity:

- `normal`: no affixes
- `magic`: small affix count
- `rare`: larger affix count
- `unique`: authored special rules

Current simple budget is acceptable during prototype.

Future direction:

- magic: 1-2 affixes
- rare: 3-4 affixes for Roblox readability
- unique: no random affix budget by default; use authored capabilities/modifiers

Do not copy PoE's full rare complexity blindly. Roblox item readability matters more.

## Crafting / Modification Direction

Keep crafting approachable.

Good first modification actions:

- reroll all affixes on an item
- upgrade rarity
- upgrade one affix tier when allowed
- lock one affix before rerolling
- reroll base values within the same base range

Avoid early:

- complicated modifier blocking
- large currency families
- hidden crafting states
- mandatory late-game crafting

## Equipment Visual Profiles

Supported modes:

1. `socketed`
   - one rigid asset attached to one socket
   - weapons, shields, simple accessories

2. `segmented`
   - multiple rigid assets bound to multiple sockets
   - shoulders, belts, upper-leg flaps, layered armor

3. `skinned`
   - skinned mesh/bone-driven gear
   - robes, coats, torso armor that must deform with animation

## Character Rig Socket Contract

Current canonical socket names for `R6` profiles:

- `Weapon_Main`
- `Weapon_Offhand`
- `Armor_Chest`
- `Armor_LeftShoulder`
- `Armor_RightShoulder`
- `Armor_LeftHipUpper`
- `Armor_RightHipUpper`
- `Armor_WaistFront`
- `Armor_WaistBack`

Authoring expectations:

1. Character models should expose `Attachment` instances with those exact names.
2. Attachments should live on the part that conceptually owns the motion for that segment.
3. Raw part-name fallback remains temporary migration support only.
4. New profiles should target canonical socket names.

## Migration Phases

### Phase 0: Foundations
- [x] Add explicit shared types for equipment config and visual profiles.
- [x] Add resolver helpers so old and new defs can coexist.
- [x] Add visual profile registry.
- [x] Add rig socket contract.
- [x] Add authoring validation.

### Phase 1: Fixed Base Item Levels
- [x] Add `equipment.itemLevel` to the schema.
- [x] Make generation copy fixed base level into `meta.itemLevel`.
- [x] Update migrated equipment defs with authored item levels.
- [x] Treat explicit `meta.itemLevel` as dev/test override only.

### Phase 2: Modular Affixes
- [x] Move affix type definitions into shared item types.
- [x] Split affix content into prefix/suffix modules.
- [x] Make `AffixRegistry` an autoloader/index/policy module.
- [x] Add validation for duplicate affix ids and mismatched folder/kind.
- [x] Keep current rarity budgets during the first split.

### Phase 3: Def Cleanup
- [ ] Remove legacy fields from migrated defs:
  - `equipSlots`
  - `baseStats`
  - top-level `requirements`
  - top-level `visuals`
- [ ] Remove fallback logic once all equipment defs use explicit config.
- [ ] Stop deriving affix context from tags/slots after all equipment defs declare it.

### Phase 4: Item Content Packages
- [x] Decide package folder layout.
- [x] Support package-local item defs.
- [x] Support package-local single-use visual profiles.
- [ ] Keep shared visual profiles for reusable or rig-specific appearances.
- [x] Migrate first equipment packages:
  - `IronSword`
  - `LeatherChest`

### Phase 5: Loot Eligibility
- [ ] Add loot-table support for base item level gates.
- [ ] Add area/enemy/boss eligibility filters.
- [ ] Add rarity policy hooks per source if needed.
- [ ] Keep server authoritative over generation.

### Phase 6: Visual Runtime Completion
- [ ] Migrate `LeatherChest` to a real segmented profile when assets exist.
- [ ] Add live character-rig validation helpers.
- [ ] Decide when skinned armor support is actually needed.

### Phase 7: Repository / Service Cleanup
- [ ] Remove the old `EquipmentService` shim once repositories own state directly.
- [ ] Point visual replication and projection only at repository/domain entrypoints.

## Guardrails

1. Do not expand the old top-level `visuals` format.
2. Do not add more affixes to the monolithic registry.
3. Keep fixed base item level as authored content, not mutable progression.
4. Make generation server-owned.
5. Keep crafting optional and readable.
6. Prefer explicit authoring and validation over inferred behavior.

## Immediate Implementation Slice

1. Add fixed `equipment.itemLevel` support.
2. Update first migrated defs with fixed base item levels.
3. Split current affixes into individual modules.
4. Convert `AffixRegistry` into an autoloading policy registry.
5. Keep all gameplay behavior equivalent after the split.
