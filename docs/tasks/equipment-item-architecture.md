# Equipment + Item Architecture Refactor

## Goal
Build a production-friendly item and equipment system inspired by Path of Exile's loot model, but tuned for a Roblox dungeon crawler.

The target system should support:

- fixed-level base equipment
- rolled base modifiers from authored ranges
- modular affixes with item-level gated tiers
- weapon-local damage/speed/range profiles that do not pollute global player stats
- skill requirements that can validate weapon/offhand/loadout conditions
- an adaptive default offensive skill that uses the current combat loadout
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

6. Weapon base stats are local to weapon execution.
   - weapon base damage, attack speed, range, crit base, and weapon tags belong to a weapon profile
   - they should not project directly into global player stats
   - global stat modifiers can still affect attacks after the weapon profile is selected
   - this prevents a sword from globally speeding up or empowering unarmed attacks

7. Default offense should be one adaptive `BasicAttack`.
   - `BasicAttack` inspects the combat loadout and chooses an execution profile
   - unarmed, sword, bow, staff, and dual-wield behavior should be profile-driven
   - dedicated skills are still allowed for meaningful abilities, not for every primitive weapon action

8. Equipment requirements should hard-block equip by default.
   - if level/stat/attribute/slot requirements fail, the server rejects the equip request
   - failed requirements should not leave gear equipped with silently suppressed effects
   - suppression can remain a future status/debuff mechanic, not the standard equip path

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
- `weapon`
- `offhand`

This replaces the legacy loose fields:

- `equipSlots`
- `baseStats`
- top-level `requirements`
- top-level `visuals`

Those legacy fields should remain only during migration.

### Weapon Config

Weapons should declare local combat properties inside `equipment.weapon`.

Example:

```luau
equipment = {
  itemLevel = 1,
  slots = { "Main", "Secondary" },
  class = "weapon",
  affixContext = "melee_weapon",
  requirements = {
    level = 1,
    attributes = { Strength = 5 },
  },
  weapon = {
    class = "sword",
    handedness = "one_handed",
    tags = { "weapon", "melee", "sword", "physical" },
    base = {
      attackSpeed = 1.2,
      range = 6,
      critChance = 0.05,
    },
    damage = {
      {
        type = "Physical",
        min = 8,
        max = 12,
      },
    },
    basicAttackProfile = "sword_light_1h",
  },
  visualProfileId = "iron_sword_r6",
}
```

Weapon-local values are consumed by skill/attack resolution.

They should not become projected global stats:

- `weapon.base.attackSpeed` is the weapon's base action tempo
- `weapon.damage` is the weapon's base damage range
- global attack speed and damage modifiers apply later in the attack context

Tempo rule:

```text
finalTempo = weapon.attackSpeed * globalAttackSpeedMultiplier * skillTempoMultiplier
```

Higher `attackSpeed` means faster attacks.

### Offhand Config

Not every secondary-slot item is a weapon.

Secondary items can declare `equipment.offhand`:

```luau
offhand = {
  type = "shield",
  tags = { "shield", "block" },
  allowedSlots = { "Secondary" },
  blockProvider = true,
}
```

Examples:

- shield: supports block skills and may provide armor/resistance
- quiver: supports bow skills, visually attaches to back, occupies secondary
- catalyst/focus: supports spell skills, may not be used for physical attacks
- secondary weapon: can be used by weapon-aware skills when compatible

### Projected Equipment Effects vs Local Weapon Stats

Use this split:

Projected effects:

- armor
- attributes
- global increased attack speed
- global increased damage
- granted skills
- animation overrides

Weapon-local stats:

- base weapon damage
- base weapon attack speed
- weapon range
- weapon crit base
- weapon damage type
- weapon attack profile
- weapon-specific affix rolls

Affix/modifier entries should eventually include an explicit scope:

- `global`: projected into player stats
- `attribute`: projected into player attributes
- `weapon`: applied to the weapon profile only
- `skill`: modifies specific skill behavior

Example:

```luau
{
  scope = "weapon",
  kind = "flat",
  target = "PhysicalDamage",
  min = 3,
  max = 7,
}
```

This is required so a sword's base damage/speed does not affect unrelated skills.

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

## Combat Loadout Snapshot

Equipment projection and combat loadout are separate concepts.

Projection answers:

`What global stats/attributes/skills does this gear grant?`

Combat loadout answers:

`What weapons/offhand tools can the character currently use for skill execution?`

Add a server-owned `CombatLoadoutResolver` that reads equipment state and emits a `CombatLoadoutSnapshot`.

Example:

```luau
{
  main = {
    uid = "...",
    itemId = "iron_sword",
    weaponClass = "sword",
    tags = { "weapon", "melee", "sword", "physical" },
    attackSpeed = 1.2,
    damage = {
      { type = "Physical", min = 8, max = 12 },
    },
    profile = "sword_light_1h",
  },
  secondary = {
    uid = "...",
    itemId = "wooden_shield",
    offhandType = "shield",
    tags = { "shield", "block" },
  },
  modes = {
    canBlock = true,
    canDualWield = false,
    canRangedAttack = false,
  },
}
```

The server recomputes this snapshot after equip/unequip and replicates it to the client.

Client snapshots are for UI/preflight only; the server remains authoritative.

## Skill Requirements and Weapon Awareness

Skills should declare explicit usage requirements.

Example:

```luau
requirements = {
  weapon = {
    mode = "any",
    classes = { "sword", "axe", "dagger" },
    tags = { "melee" },
    allowUnarmed = false,
  },
}
```

Recommended requirement modes:

- `adaptive`: choose the best valid profile from current loadout
- `any`: any valid weapon/offhand can satisfy the skill
- `main`: must use main weapon
- `secondary`: must use secondary weapon/offhand
- `both`: skill intentionally uses both hands
- `optional`: weapon can enhance the skill but is not required

Validation should happen in two places:

1. client preflight for UX
2. server authoritative validation before execution

Server rejection reasons should be structured:

- `requires_weapon`
- `wrong_weapon_class`
- `wrong_weapon_tags`
- `requires_shield`
- `requirements_not_met`
- `offhand_blocked`

## Adaptive BasicAttack

The default offensive primitive should become `BasicAttack`.

`BasicAttack` should:

- use unarmed profile if no compatible weapon exists
- use main weapon when only main is valid
- use secondary weapon when only secondary is valid
- alternate between both valid one-handed weapons when the profile does not define special dual-wield behavior
- use a specific dual-wield profile when the selected weapon/profile declares one
- never require the player to manage separate basic skills for every weapon type

Dedicated skills remain separate for meaningful abilities:

- `ManaBall`
- `SwordCleave`
- `ShieldBlock`
- `Dash`
- `DodgeRoll`

Dedicated skills can still be weapon-aware through requirements.

## Basic Attack Profiles

Weapon-specific behavior should live in profiles, not in item inventory logic.

Example profiles:

- `unarmed_basic`
- `sword_light_1h`
- `dual_blade_light`
- `bow_basic`
- `staff_basic`

Example:

```luau
{
  id = "sword_light_1h",
  weaponClasses = { "sword" },
  combo = {
    steps = 3,
    stepDurations = { 0.42, 0.4, 0.55 },
    hitDelays = { 0.22, 0.2, 0.3 },
    window = 0.55,
  },
  steps = {
    {
      hand = "main",
      animation = "Sword_1H_Slash_1",
      damageMultiplier = 1.0,
    },
    {
      hand = "main",
      animation = "Sword_1H_Slash_2",
      damageMultiplier = 1.0,
    },
    {
      hand = "main",
      animation = "Sword_1H_Heavy_3",
      damageMultiplier = 1.35,
    },
  },
}
```

Profiles should drive:

- combo step count
- animation keys
- hit timing
- hitbox shape/range
- hand selection
- damage coefficient
- whether both weapons are used

## Dual Wield Resolution

Dual wield does not require a special "paired weapon" item.

The normal case is:

- player equips one one-handed weapon in `Main`
- player equips another one-handed weapon in `Secondary`
- skill resolver decides which weapon(s) the skill can use

The resolver should be permissive and deterministic:

1. Build candidate weapons from equipped hands.
2. Filter candidates by the skill/profile requirements.
3. If only one weapon is valid, use that weapon.
4. If both weapons are valid and the skill has no special dual-wield behavior, alternate hands between uses/steps.
5. If both weapons are valid and the skill/profile declares `hand = "both"`, combine both weapon contexts.
6. If neither weapon is valid, reject or fall back to unarmed only if the skill allows unarmed.

This means unusual loadouts should not break the resolver.

Examples:

- sword + sword, `BasicAttack`: alternate unless a dual-sword profile exists
- dagger + wand, sword-only skill: use dagger only if dagger satisfies requirements, otherwise reject
- dagger + wand, generic adaptive `BasicAttack`: use whichever equipped item has a valid basic attack profile, alternating only when both profiles are compatible
- sword + shield, `ShieldBlock`: use shield
- sword + shield, `BasicAttack`: use sword
- bow + quiver: bow attacks use bow, quiver acts as support/offhand data

Paired weapon items can exist later as a special item class, but they are not the default dual-wield model.

## Weapon Mastery Direction

Do not implement full mastery in the first combat-loadout pass.

Keep the system ready for it by routing `BasicAttack` through profiles.

Future `WeaponMasteryService` can modify:

- selected basic attack profile
- combo step count
- step animations
- damage coefficients
- stamina cost
- special proc rules

Example progression:

- sword mastery 1: basic 2-hit combo
- sword mastery 5: 3-hit combo
- sword mastery 10: choose fast combo branch or heavy finisher branch

Other skills can later scale with mastery, but early implementation should keep them stable and readable.

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

---

# Resolved Decisions (2026-07-29)

These close the open questions that were blocking Phases 11-13. They are decided, not proposals.

## D1. Weapon base damage is fixed; instance variance comes from affixes

`weapon.damage` is **literally the per-hit range** for every copy of that base. Every Iron Sword hits for 8-12. Two Iron Swords differ only by their affixes.

- per-hit damage rolls uniformly in `[min, max]` at swing time
- no generation-time roll of weapon base damage
- `meta.weaponDamageRolls` is deleted
- `EquipmentRollService.rollWeaponDamage` is deleted
- `scaleMinPerItemLevel` / `scaleMaxPerItemLevel` are removed from weapon damage (item-level scaling stays on `baseRolls` and affix tiers, which are item level, not player level)

Rationale: this is what PoE actually does, it deletes code rather than adding it, and it makes "is this sword better?" answerable by reading the affix list.

## D2. Damage pipeline: weapon provides base, `PhysicalDamage` becomes added flat

```text
final = (weaponBase + addedFlat) * (1 + increased%)
```

- base damage comes from the equipped weapon, or from the unarmed profile when empty-handed
- the global `PhysicalDamage` stat becomes **flat added damage**, not a base
- unarmed stops being a special case: it is just a profile with its own base

Consequences to expect:

- Iron Sword must be rescaled from `50-70` to `~8-12`
- unarmed base becomes `~2-4`
- with `PhysicalDamage` base 10: unarmed lands ~12-14, armed ~18-22
- `PhysicalDamage` base 10 may want lowering once gear is the dominant source, but that is tuning, not architecture

## D3. Tempo composes multiplicatively; the weapon sets the base

```text
tempo = weaponAttackSpeed * AttackSpeedStat * skillTempoMultiplier
```

`SkillTimingResolver.resolve` gains an optional `weaponTempo` argument. The `AttackSpeed` stat keeps its current meaning as a global multiplier (base `1.0`). Weapon attack speed is **never** projected into the stat.

## D4. Delivery is sliced: prove the pipe, then build on it

Phase A wires one end-to-end path with the simplest possible consumer and is verified in Studio before Phase B starts. Rationale: Phases 1-10 built a complete supply chain with zero consumers, and that is exactly how the current no-ops accumulated.

## D5. Smaller calls made along the way

- **`requirements.level`**: keep the schema field so content does not churn when progression lands, but the authoring validator emits a warning that it is unenforced. This kills the silent no-op without building a levelling system. Level-based logic is explicitly deferred — the level API is likely to change and is not worth integrating against yet.
- **Post-equip requirement loss**: keep the existing projection suppression path (`active = false`, `suppressedReason`). Hard-block covers the equip moment; suppression covers requirements lost afterwards (debuffs, respec). Both are wanted; they are not redundant.
- **2H equip with an occupied Secondary**: hard reject during Phase A; **superseded by D10**, which auto-unequips the secondary.
- **`IronSword` `Strength = 0`**: remove; a requirement that can never fail is noise.

## D7. Weapon damage is typed end to end

*(Decided after Phase B verification. D6 lives in the Phase B section.)*

Damage carries its type from the weapon all the way to the attack packet. A basic wand deals
Magic, a flame wand deals Fire, a flame sword deals both.

- `BaseSkill:resolveWeaponDamage` returns `{ { type, amount } }` — one entry per authored damage
  range, not a single collapsed number
- the global flat damage bonus is **type-matched**: `Physical` is scaled by `PhysicalDamage`,
  `Magic` by `MagicDamage`, using the same `<Type>Damage` convention as weapon-scoped modifier
  targets. A type with no matching stat (there is no `FireDamage`) simply gets no flat bonus —
  a legitimate authoring state, not an error
- `AttackResolver` accepts `baseAttack.damages` and emits one packet per entry; the single-type
  `damage` + `damageType` form is untouched and still used by every non-weapon skill

Why this mattered enough to fix immediately: before it, a wand rolled Magic damage, had the
**`PhysicalDamage`** stat added to it, and was labelled `Physical` in the packet — wrong type and
wrong number, with `MagicDamage` doing nothing at all. `AttackPacket.damageType` was already a
free-form string, so the truncation was entirely in the resolver layer.

**Decision index:** D1–D5 and D7 above; D6 in the Phase B section; D8–D10 in the Phase C section.
Decisions are placed next to the phase they govern once a phase exists for them.

---

# Implementation Plan

## Agent Handoff Brief — Phase A

**Scope boundary: implement Phase A only.** Do not start Phase B or C. Do not build a levelling system. Do not touch the UI runtimes (`EquipmentPanelRuntime`, `EquipmentMenuRuntime`, `SlotVisuals`) — they have unrelated uncommitted work in them.

**Files in scope, in dependency order:**

| # | File | Change |
|---|------|--------|
| 1 | `src/shared/items/ItemTypes.luau` | `scope` on `ModifierEntry` + `AffixModifierRollDef`; `WeaponDamageRoll` → `WeaponDamageRange` (drop scale fields); drop `ItemMeta.weaponDamageRolls`; collapse snapshot `secondary`/`offhand` |
| 2 | `src/shared/items/EquipmentDefUtils.luau` | add `resolveScope` / `isProjectedScope` / `isWeaponScope`; `getWeaponDamageRolls(def, item)` → `getWeaponDamage(def)` |
| 3 | `src/server/Inventory/Generation/EquipmentRollService.luau` | carry `scope` in `rollBaseModifier`; delete `rollWeaponDamage` and its call block |
| 4 | `src/server/Inventory/Generation/AffixRollService.luau` | carry `scope` in `makeRolledModifier` |
| 5 | `src/server/Inventory/Projection/CapabilityResolver.luau` | project only `global`/`attribute` scoped entries |
| 6 | `src/server/Inventory/CombatLoadout/CombatLoadoutResolver.luau` | fold weapon-scoped modifiers into the weapon; new secondary shape; fix closure refinement |
| 7 | `src/shared/items/Affixes/Prefixes/Fury.luau`, `Suffixes/OfTheFairy.luau` | mark weapon-context entries `scope = "weapon"` |
| 8 | `src/shared/items/Equipment/IronSword/init.luau` | rescale damage `50-70` → `8-12`; drop `Strength = 0` |
| 9 | `src/shared/Config/CombatConfig.luau` *(new)* | unarmed base damage/speed/range |
| 10 | `src/server/SkillsFramework/Skills/BaseSkill.luau` | add `resolveWeaponDamage(hand)` |
| 11 | `src/server/SkillsFramework/Skills/Punch.luau` | use `resolveWeaponDamage` instead of `resolveStat(PhysicalDamage)` |
| 12 | `src/shared/skills/SkillTimingResolver.luau` | optional `weaponTempo` argument |
| 13 | `src/server/SkillsFramework/SkillTimingService.luau` | pass main-hand attack speed |
| 14 | `src/client/Inventory/CombatLoadoutMirror.luau` *(new)* + `client/.../BaseSkill.luau` | client-side tempo without coupling skills to `InventoryClient` |
| 15 | `src/server/Inventory/Validation/EquipmentAuthoringValidator.luau` | weapon-context scope validation; `requirements.level` warning |

### Known traps (found while prototyping this — do not rediscover them)

1. **Do not route static capabilities through a scope-based container selector.** In `CapabilityResolver`, `staticCapabilities.stats` and `staticCapabilities.attributes` declare their container by *which list they are in*, not by scope. If you push them through a shared `project()` helper that picks the container from scope, every unmarked attribute capability silently re-classifies as a stat. Only rolled base modifiers and affix modifiers should use scope-based container selection.

2. **`resolveScope` must honor the legacy `meta.container == "attribute"` marker.** That marker predates scopes and is how `Fury`'s Strength roll and `OfTheFairy`'s Dexterity/Intelligence rolls currently reach attributes. If `resolveScope` returns `"global"` for them, attribute affixes break.

3. **Only `melee_weapon` context entries become weapon-scoped.** Precisely:
   - `Fury.luau:6` (`meleeWeaponTier1` PhysicalDamage) → `scope = "weapon"`
   - `Fury.luau:19` (`meleeWeaponTier2` PhysicalDamage) → `scope = "weapon"`
   - `OfTheFairy.luau:6` (`meleeWeaponTier1` CriticalHitChance) → `scope = "weapon"`
   - **Leave alone:** `gloves` AttackSpeed (gloves granting global attack speed is a legitimate projected effect per this doc), `body_armor` entries, and all `any` entries. `any` is the fallback for rings/amulets, where flat PhysicalDamage means exactly the added-flat-damage of D2.
   - `OfSwiftness.luau` has no weapon context; no change.

4. **`CombatLoadoutResolver` closure refinement.** `main` and `secondary` are assigned inside the nested `resolveSlot` function, so Luau drops the nil-refinement at the `main.handedness` read (line 111 today). Restructure so `resolveSlot` *returns* its result instead of mutating upvalues.

5. **After deleting `rollWeaponDamage`, check for newly-unused locals** in `EquipmentRollService`. `isInteger`, `roundValue`, and `rng` are all still used by `rollBaseModifier` — but selene will flag anything that genuinely goes unused.

6. **`EquipmentDefUtils` forward references are fine.** A helper defined near the top of the module may call `EquipmentDefUtils.getBaseModifiers` defined further down; it is a table field lookup resolved at call time.

7. **`Punch` currently multiplies by per-step multipliers** (`0.8 / 0.9 / 1.25` at `Punch.luau:38`). Keep that behavior — apply the step multiplier to the resolved weapon damage, do not delete it.

### Validation available in this repo

No compile or test pipeline. Verify with Luau + selene diagnostics in the IDE, then Studio playtest against the Phase A exit criteria below. Report exact console output for any runtime error rather than guessing.

## Phase A — make the pipe real

Goal: equipping a sword visibly changes a hit in Studio, and a weapon affix stops leaking into unarmed attacks.

### A1. Scope enforcement (fixes the live bug — do this first)

Types (`src/shared/items/ItemTypes.luau`):
- add `scope: ModifierScope?` to `ModifierEntry`
- add `scope: ModifierScope?` to `AffixModifierRollDef`
- document the default: `nil` means `global`

Roll paths (both currently drop the field):
- `EquipmentRollService.rollBaseModifier` — carry `rollDef.scope` through
- `AffixRollService.makeRolledModifier` — carry `rollDef.scope` through

Consumers:
- `CapabilityResolver.resolve` — project only `global` (nil-default) and `attribute` scoped entries. Skip `weapon` and `skill`.
- `CombatLoadoutResolver` — becomes the home for weapon-scoped modifiers: fold `scope = "weapon"` entries from the item's own affixes and base modifiers into that weapon's damage/attackSpeed/crit. Scope `weapon` means "applies to the item it is attached to", nothing else.

Content fix (this is the live Guardrail 7 violation):
- `Fury.luau` — mark the `melee_weapon` `PhysicalDamage` and `AttackSpeed` entries `scope = "weapon"`
- audit `OfTheFairy.luau` and `OfSwiftness.luau` the same way
- `body_armor` context entries stay global

  > Implementation note (Phase A, 2026-07-29): this bullet is imprecise vs. known trap #3 below.
  > There is no `AttackSpeed` entry inside Fury's `melee_weapon` context — Fury's `AttackSpeed`
  > entries live under `gloves` and are correctly left global. Only the three entries listed in
  > trap #3 were marked `scope = "weapon"`. Followed the trap table over this prose since the
  > traps were written after the prototype run that actually hit this.

Validation:
- `EquipmentAuthoringValidator` — error when an affix modifier in a weapon context targets a weapon-local stat (`PhysicalDamage`, `AttackSpeed`, `CriticalHitChance`) without an explicit `scope`. Explicit over inferred, fail fast.

### A2. Weapon damage schema — fixed base

- rename `WeaponDamageRoll` to `WeaponDamageRange`; drop the two `scale*PerItemLevel` fields
- delete `EquipmentRollService.rollWeaponDamage`
- delete `weaponDamageRolls` from `ItemMeta`
- `EquipmentDefUtils.getWeaponDamageRolls(def, item)` becomes `getWeaponDamage(def)` — reads the def only, no instance
- rescale `IronSword` damage `50-70` to `8-12`

### A3. Unarmed base + damage pipeline

New `src/shared/Config/CombatConfig.luau` as a stepping stone (Phase B moves this into the `unarmed_basic` profile):

```luau
UNARMED = {
  damage = { { type = "Physical", min = 2, max = 4 } },
  attackSpeed = 1.0,
  range = 4.5,
}
```

New `BaseSkill:resolveWeaponDamage(hand)` on the server:
1. read `CombatLoadoutService.get(self.casterId)`
2. select the weapon for `hand`, else fall back to `CombatConfig.UNARMED`
3. roll per-hit uniformly in `[min, max]`
4. add the flat `PhysicalDamage` stat
5. hand the result to the existing `resolveAttack`

`Punch:onComboStep` swaps `resolveStat(PhysicalDamage) * mult` for `resolveWeaponDamage() * mult`. Everything downstream (`AttackResolver`, modifiers, hitbox) is untouched.

### A4. Tempo composition

- `SkillTimingResolver.resolve(skillTags, statLookup, weaponTempo: number?)` — `tempo = (weaponTempo or 1) * statValue`
- server: `SkillTimingService.resolve` reads `CombatLoadoutService.get(entityId)` and passes main-hand attack speed
- client: `client/SkillsFramework/Skills/BaseSkill.luau:464` needs the same number

Coupling note: client skills must **not** require `InventoryClient` directly. Add a thin `src/client/Inventory/CombatLoadoutMirror.luau` that `InventoryClient` feeds and skills read. Keeps the ownership boundary the design principles ask for, and gives client prediction a stable source.

### A5. Snapshot shape cleanup (do before Phase B multiplies consumers)

`CombatLoadoutSnapshot` currently has both `secondary` and `offhand` for one physical slot, so every consumer has to check both. Collapse:

```luau
secondary: {
  kind: "weapon" | "offhand",
  weapon: CombatLoadoutWeapon?,
  offhand: CombatLoadoutOffhand?,
}?
```

Also restructure `CombatLoadoutResolver.resolve` so `main`/`secondary` are not closure-mutated upvalues — the `main.handedness` read at line 111 relies on a refinement Luau drops for locals assigned inside a nested function.

### A6. Honest no-ops

- `EquipmentAuthoringValidator` warns on `requirements.level` (unenforced; no progression system)
- remove `Strength = 0` from `IronSword`

### Phase A status: COMPLETE — verified in Studio 2026-07-29

Confirmed by playtest: damage rises on equipping Iron Sword, a magic sword's rolled `+2 Physical
Damage` applies while armed, and unequipping returns damage to the unarmed baseline with the affix
bonus gone. Startup validation reports only the two expected `requirements.level` warnings.

Follow-ups carried out of Phase A:

1. ~~**`applyWeaponScopedModifiers` hardcodes three target names.**~~ **RESOLVED** (before Phase B).
   Damage targets are now derived by name via `EquipmentDefUtils.weaponDamageTypeForTarget`
   (`<Type>Damage` → type), `percent` damage modifiers are supported, and a flat modifier for a
   type the weapon lacks creates that range instead of vanishing. Anything still unconsumable
   `warn`s with item id and target. `EquipmentAuthoringValidator` gained the startup half: it uses
   the same shared predicate, so a weapon-context `MagicDamage` roll without explicit scope is now
   an error (it previously would have leaked globally — the Guardrail 7 bug waiting for the first
   wand), and a `scope = "weapon"` roll on a non-weapon-local target is rejected outright.
2. **Nothing has been type-checked.** No Luau language server was attached during any phase;
   `getDiagnostics` returned empty for every file throughout. Worth a pass in-editor. **Still open.**
3. ~~**`resolveWeaponDamage` reads only `weapon.damage[1]`.**~~ **RESOLVED** (see D7).
4. **Only the main hand is consulted** anywhere. Dual wield is Phase C. **Still open.**

### Phase A exit criteria — verified in Studio

1. Unarmed punch deals ~12-14
2. Equip Iron Sword: damage ~18-22, swings visibly faster (1.2x tempo)
3. Equip a magic Iron Sword rolled with `Fury`: damage and speed increase further **while armed**
4. Unequip: punch returns to ~12-14 and the `Fury` bonus is gone — this is the proof that scope enforcement works
5. Startup validation reports no new errors

## Phase B — profiles and adaptive BasicAttack

Phase A is confirmed in Studio, so this is cleared to start.

### D6. Profile resolution: profile-keyed shared spec

Profiles are **shared content**, and each side resolves the active one independently from the
combat loadout it already holds. No new replication.

```text
CLIENT: CombatLoadoutMirror -> main.basicAttackProfile -> registry -> combo/anim
SERVER: CombatLoadoutService -> main.basicAttackProfile -> registry -> combo/anim
```

Both sides read byte-identical profile data, so client prediction matches server execution for
free. Rejected: server-pushed resolved specs (adds a replication path and a desync window during
equip), and one-skill-per-weapon-type (violates Guardrail 8).

**This is the load-bearing constraint of Phase B.** Today the client predicts combos from a static
per-skill spec — `BasicComboSkill` reads `config.anim.comboSteps` and `combo.steps` straight out of
`Specs/Punch.luau`. Adaptive `BasicAttack` must make that lookup dynamic without breaking the five
existing skills that rely on the static path.

## Agent Handoff Brief — Phase B

**Scope boundary: Phase B only.** Do not start Phase C (skill requirement gates, dual wield). Do
not touch the UI runtimes. Do not build a levelling system. Only the main hand is consulted —
secondary-hand and dual-wield resolution is explicitly Phase C.

**Files in scope, in dependency order:**

| # | File | Change |
|---|------|--------|
| 1 | `shared/skills/BasicAttackProfileTypes.luau` *(new)* | `BasicAttackProfile` type: `id`, `weaponClasses`, `combo`, `steps` (hand/animation/damageMultiplier), `hitCone` |
| 2 | `shared/skills/BasicAttackProfiles/unarmed_basic.luau` *(new)* | Absorbs `CombatConfig.UNARMED` damage/speed/range; carries Punch's current 3-step combo + anim keys |
| 3 | `shared/skills/BasicAttackProfiles/sword_light_1h.luau` *(new)* | Sword profile; `weaponClasses = { "sword" }` |
| 4 | `shared/skills/BasicAttackProfileRegistry.luau` *(new)* | Autoload the folder, validate ids/steps, index by id **and** by weapon class; expose `resolve(loadout)` |
| 5 | `shared/Config/CombatConfig.luau` | Delete once `unarmed_basic` owns the unarmed base — it was an explicit Phase A stepping stone |
| 6 | `server/SkillsFramework/Skills/BaseSkill.luau` | `resolveWeaponDamage` reads the unarmed fallback from `unarmed_basic`, not `CombatConfig` |
| 7 | `server/SkillsFramework/SkillsData/BasicAttack.luau` *(new)* | Server config. Autoloads — no registration needed |
| 8 | `server/SkillsFramework/Skills/BasicAttack.luau` *(new)* | Server class. **Filename must equal the skill name** (see trap 1) |
| 9 | `shared/skills/Specs/BasicAttack.luau` *(new)* | Client spec; resolves combo/anim through the registry rather than hardcoding |
| 10 | `shared/skills/ClientSpec.luau` | Add the `BasicAttack` entry — this map is **manual**, not autoloaded (trap 2) |
| 11 | `client/SkillsFramework/Skills/BasicComboSkill.luau` | Allow combo/anim to come from a resolved profile while the static path keeps working for the other five skills |
| 12 | `server/dev/InitDev.luau` | `addSkill(playerId, "BasicAttack")` |
| 13 | `client/dev/InitDev.luau` | `SkillSlots.assign(1, "BasicAttack")` in place of `"Punch"` |

`Punch` stays on disk as the unarmed implementation detail until Phase C retires it. Do not delete
it — `SkillsData/` autoloads, so an orphaned entry is harmless, and keeping it makes rollback easy.

### Known traps

1. **Server skill class filename must equal the skill name.** `SkillsConfig.addSkill` does
   `require(SkillsFolder:WaitForChild(name))` — so `Skills/BasicAttack.luau` exactly. The *client*
   class is chosen differently, by `spec.class` string, resolved against
   `client/SkillsFramework/Skills/`. These two lookups do not work the same way; do not assume
   symmetry.

2. **`SkillsData/` autoloads but `ClientSpec.luau` does not.** `SkillsConfig` iterates
   `SkillsDataFolder:GetChildren()`, so a new server data file just appears. `ClientSpec` is a
   hand-written map. Miss the entry and the failure is the silent one this project keeps producing:
   the server grants the skill, the client warns `no client spec for skill`, and the keybind does
   nothing.

3. **Do not break the five existing skills.** `BasicComboSkill` is shared by `Punch` and
   `TripleStrike`. Profile resolution must be additive — if a spec carries no profile binding, the
   existing static `config.anim.comboSteps` path must behave exactly as it does now.

4. **Client and server must resolve the same profile from the same input.** The whole point of D6
   is that neither side invents data. If the two resolve differently, prediction desyncs and hits
   land at the wrong time. Keep the resolution function in `shared/`, called by both — do not
   reimplement it per side.

5. **`weapon.basicAttackProfile` may name a profile that does not exist.** `IronSword` already
   declares `basicAttackProfile = "sword_light_1h"`. Resolution must fall back to `unarmed_basic`
   on an unknown id and log it — do not silently produce an empty combo.

6. **Registry validation should error on unknown weapon classes**, matching the fail-fast stance
   `EquipmentAuthoringValidator` already takes. Prefer a startup error over a mystery at swing time.

7. **`[InputFlow]` logging is live and flag-gated** (`DebugConfig.isEnabled("inputFlow")`, enabled
   in client `dev/InitDev`). Use it — `registerSkill` already logs which path registered a skill,
   which is how you confirm `BasicAttack` reached the client at all.

### Validation

No compile step or test suite. Use `mcp__ide__getDiagnostics` for Luau/selene, but note that no
language server was attached during Phase A — an empty result means "nothing reported", not
"clean". Report that honestly rather than implying a passing typecheck.

Do not claim runtime success; Studio playtesting is the developer's step.

### Phase B status: COMPLETE — verified in Studio 2026-07-29

Confirmed by playtest: the bound key resolves `sword_light_1h` with Iron Sword equipped and reverts
to `unarmed_basic` on unequip, with no separate keybind. `TripleStrike` behaves identically armed
and unarmed (the static `BasicComboSkill` path is untouched — trap 3 held). NPC `Punch` attacks
still work after the D7 typed-damage change.

Note: sword swing animations are not authored yet (`Sword_1H_Slash_1/2/Heavy_3` do not exist), so
the sword profile currently plays no animation. Profile resolution, timing, and damage are all
confirmed working regardless; authoring those assets is content work, not a code gap.

Follow-ups carried out of Phase B:

1. **Client hit-cone values in `Specs/BasicAttack.luau` are static** (65/6) rather than
   profile-resolved. Cosmetic only — this feeds local `ImmediateHitFeedback`, not real hit
   detection, which is fully profile-driven server-side.
2. **Trap 6 was interpreted narrowly.** The registry errors on *duplicate/ambiguous* weapon-class
   ownership rather than on unknown weapon classes, since `weapon.class` is a free-form string with
   no authoritative list to check against. A typo'd `weaponClasses = { "swrod" }` is therefore
   still not caught at startup. Worth revisiting if a weapon-class registry ever exists.
3. **Projectile behavior is not profile-driven.** A flame wand firing a fire projectile needs
   profiles to declare projectile behavior; D7 covers the damage side only.

### Phase B exit criteria — verified in Studio

1. Unarmed: bound key produces the current 3-step Punch combo, unchanged in feel and damage.
2. Equip Iron Sword: the **same** bound key produces the sword combo — different step count,
   timings, and animations — with no separate keybind.
3. Unequip: reverts to the unarmed combo.
4. `TripleStrike`, `Dash`, `DodgeRoll`, `ManaBall`, `CascadingManaBalls` all still work
   (regression check on the shared `BasicComboSkill` path).
5. Client-predicted animation timing matches server hit timing in both profiles — no visible
   desync between swing and damage.
6. Startup validation reports no new errors.

## Phase C — skill gates and dual wield

Phases A and B are confirmed in Studio, so this is cleared to start.

### D8. Requirements gate eligibility; profiles decide execution

Two layers with one job each. They both read the combat loadout, but they answer different
questions and must not be merged.

```text
LAYER 1  gate       "can this skill be used at all?"   -> requirements.weapon
LAYER 2  resolution "how does it execute?"             -> BasicAttackProfileRegistry
```

- `ShieldBlock` declares `requirements.weapon` needing a shield; without one the server rejects
- `BasicAttack` declares `mode = "adaptive"`, which means **never gated** — profile resolution
  already handles compatibility and falls back to `unarmed_basic`
- `adaptive` is declared explicitly rather than inferred from an absent field (Guardrail 6)

Rejected: folding profile compatibility into the requirement schema. `BasicAttackProfileRegistry`
already indexes by weapon class; a second authority on the same question would drift.

### D9. Hand alternation resets each combo

When both hands hold valid one-handed weapons and the profile step does not name a hand, alternation
starts on **main** at the beginning of every combo.

```text
combo 1: main -> off -> main
combo 2: main -> off -> main
```

The same input always produces the same hand sequence. This is Guardrail 9's "permissive but
deterministic" applied to hands: main swings marginally more often, and that is the accepted cost of
being reproducible and testable. An authored `hand` on a profile step always wins over alternation.

### D10. Two-handed equip auto-unequips the secondary

Equipping a two-hander with the Secondary slot occupied moves the secondary item to inventory and
completes the equip. It rejects only when the inventory is full, with reason `inventory_full`.

This supersedes the Phase A decision to keep the hard reject (D5), which was deferred to here.
Note this is the first place the equip path moves an item the player did not directly ask to move —
it must be a single atomic operation, never a partial state where the secondary is unequipped but
the two-hander failed to equip.

## Agent Handoff Brief — Phase C

**Scope boundary: Phase C only.** This is the last phase of this refactor. Do not build a levelling
system. Do not touch the UI runtimes. Do not add weapon mastery (explicitly deferred in this doc).

**Files in scope, in dependency order:**

| # | File | Change |
|---|------|--------|
| 1 | `shared/skills/SkillRequirementTypes.luau` *(new)* | `WeaponRequirement` type: `mode`, `classes`, `tags`, `allowUnarmed`, `offhandType` |
| 2 | `server/SkillsFramework/SkillsConfig.luau` | Add `requirements` to the `SkillData` and `SkillConfigOverride` types |
| 3 | `shared/skills/SkillRequirementResolver.luau` *(new)* | **Shared** predicate: `(requirement, loadout) -> (ok, reason)`. Both sides call this — do not write it twice (see trap 2) |
| 4 | `server/SkillsFramework/SkillsManager.luau` | Add the gate inside `useSkill`, alongside the existing cooldown/lock checks (trap 1) |
| 5 | `client/SkillsFramework/Skills/BaseSkill.luau` | Preflight in `use()` via `CombatLoadoutMirror`, next to the existing `SkillPacer.canStart` check |
| 6 | `server/SkillsFramework/SkillsData/*.luau` | Author requirements: `BasicAttack` gets `mode = "adaptive"`; others as appropriate |
| 7 | `shared/skills/BasicAttackProfileTypes.luau` | Profile steps already carry `hand`; add `"both"` as a permitted value |
| 8 | `shared/skills/HandResolver.luau` *(new)* | Deterministic candidate resolution + per-combo alternation (D9) |
| 9 | `server/SkillsFramework/Skills/BasicAttack.luau` | Use `HandResolver` for steps with no authored hand; support `hand = "both"` |
| 10 | `server/SkillsFramework/Skills/BaseSkill.luau` | `resolveWeaponDamage` already accepts `"main"`/`"secondary"`; add combined resolution for `"both"` |
| 11 | `server/Inventory/Validation/EquipmentEquipValidator.luau` | Return a structured "needs secondary unequipped" outcome rather than a flat reject |
| 12 | `server/Inventory/InventoryService.luau` | Atomic auto-unequip on two-handed equip (D10, trap 5) |

### Known traps

1. **`SkillsManager.useSkill` already has a gate sequence.** Lines ~160-215 run `canCast` →
   cooldown → session lock, each `return nil, "reason"`, and the `SkillRequestUse` handler turns
   that into `{ success = false, error = reason }`. Add the weapon gate into that existing sequence.
   Do not build a parallel rejection path — the plumbing already reaches the client.

2. **Client and server must share one requirement predicate.** Put it in `shared/` and call it from
   both. This is the same constraint as D6/trap 4 in Phase B: two implementations of "is this weapon
   valid" will drift, and the symptom is a client that lets you press a key the server then refuses.
   Remember shared code cannot require server code — pass the loadout in.

3. **`mode = "adaptive"` must never reject.** It is the declared way of saying "resolution handles
   this". If the gate ever returns false for an adaptive skill, `BasicAttack` becomes unusable
   while unarmed, which is a total loss of basic offense.

4. **Alternation state needs an owner and a reset rule.** Per D9 it resets at combo start. Decide
   where it lives (skill instance is the obvious home) and make sure it also resets on weapon swap,
   death, and respawn — a stale hand index pointing at an unequipped weapon must not be possible.

5. **The two-handed auto-unequip must be atomic.** `moveInventoryToEquipment` currently mutates
   `EquipmentRepository` and the inventory slots in sequence. Check inventory space *before* any
   mutation, and never leave a state where the secondary was unequipped but the two-hander failed to
   equip. Recompute the loadout once, after both slots settle — not between them.

6. **`resolveWeaponDamage` returns typed damage entries** (D7), not a number. `hand = "both"` must
   decide how two weapons' typed lists combine — concatenating both hands' entries is the natural
   reading, but state the choice explicitly in code comments rather than leaving it implicit.

7. **`Punch` is still live for NPCs** via the Goblin spec. It is no longer the player's basic attack
   but it is not dead code. Do not delete it, and do not break its signature.

8. **`CombatLoadoutSnapshot.secondary` is a tagged field** (`kind = "weapon" | "offhand"`), not two
   parallel fields. A shield lives at `secondary.offhand`, a second sword at `secondary.weapon`.

### Validation

No compile step or test suite. `mcp__ide__getDiagnostics` has returned empty for every file across
all phases, which means no language server is attached — an empty result is "nothing reported", not
"clean". Say so honestly rather than implying a passing typecheck.

Do not claim runtime success; Studio playtesting is the developer's step.

### Phase C exit criteria — verify in Studio

Loadout matrix, all with the same bound basic-attack key:

1. **sword + sword** — alternates main/off, resetting to main each combo (D9)
2. **sword + shield** — basic attack uses the sword; a shield-requiring skill is accepted
3. **dagger + wand** — mixed loadout resolves without error; a sword-only skill is rejected with
   `wrong_weapon_class`
4. **unarmed** — `BasicAttack` still works (proves `adaptive` never gates)
5. **two-handed equip with Secondary occupied** — secondary moves to inventory, two-hander equips,
   in one action. With a full inventory, rejects cleanly with nothing moved
6. **Rejected skill gives a structured reason** on the client, not a silent no-op
7. **Regression** — `TripleStrike`, `Dash`, `DodgeRoll`, `ManaBall`, `CascadingManaBalls` and NPC
   goblin attacks all still work

### Phase C implementation notes (agent handoff, 2026-07-29) — NOT Studio-verified

Code-complete against the 12-row table plus the consequential edits below. Not run in Studio; the
developer verifies against the exit criteria above.

**Consequential edits beyond the 12-row table** (required for the table's own rows to compile/work,
not scope creep):
- `shared/skills/SkillSpecTypes.luau` — added `requirements` to `ServerSkillConfig` (what
  `SkillsData/*.luau` actually authors against under `--!strict`; `SkillsConfig.SkillData` in row 2
  is a separate, looser type that isn't what the authored files use).
- `server/SkillsFramework/SkillMetadataService.luau` — replicates `skillData.requirements` into the
  metadata payload so the client has something to preflight against at all (row 5's client check
  needs a source; authoring the requirement twice, once per side, would recreate trap 2's drift).
- `client/SkillsFramework/SkillMetadataClient.luau` — added the matching `requirements` field to the
  `--!strict` `SkillMetadata` type.
- `shared/skills/BasicAttackProfileRegistry.luau` — relaxed the per-step `hand` assertion to allow
  `nil` (was requiring `"main"`/`"secondary"` on every step), a direct consequence of making
  `BasicAttackStepSpec.hand` optional in row 7.
- `shared/skills/BasicAttackProfiles/sword_light_1h.luau` — removed the authored `hand = "main"` from
  its three steps. Without this, D9 alternation has no observable effect anywhere in the repo's
  current content: `sword_light_1h` was the only profile that could ever apply to a dual-wielded
  loadout, and its steps hard-authored `"main"`, which always wins over alternation. `unarmed_basic`
  was left untouched (alternation is moot unarmed).

**Content gaps found — three of the seven exit criteria cannot be fully exercised with what exists
in the repo today:**
- No shield/offhand item of any kind exists (`grep -rn "offhandType\|equipment.offhand"` under
  `src/shared/items/Equipment` turns up nothing). Criterion 2's "a shield-requiring skill is
  accepted" cannot be demonstrated — there is also no `ShieldBlock` skill (or any shield-requiring
  skill) in `SkillsData`/`Skills` yet; it's still only a future example in this doc's prose.
- No second weapon class exists — `IronSword` (sword) is the only weapon item in the repo. Criterion
  3's literal "dagger + wand" loadout cannot be equipped. The `wrong_weapon_class` rejection path
  itself IS exercisable today via `TripleStrike` (see below), just not with a dagger or a wand.
- No two-handed weapon item exists anywhere in `src/shared/items/Equipment`
  (`grep -rn "two_handed"` only matches type/validator code, never a def). Criterion 5 needs one to
  equip; the D10 atomic-auto-unequip code path in `InventoryService.moveInventoryToEquipment` is
  implemented and reads correctly by inspection, but is untested against real content.

None of this was papered over — the loadout-matrix logic (`SkillRequirementResolver`, `HandResolver`,
the D10 equip path) is written to be correct for these cases generically, not special-cased to what
happens to exist. The developer will need to author a test shield/offhand item, a second weapon
class, and a two-handed weapon (even as throwaway dev-only defs) to actually drive criteria 2, 3,
and 5 in Studio.

**Requirements authored on existing skills (row 6):**
- `BasicAttack`: `mode = "adaptive"` (never gates, per D8/trap 3).
- `TripleStrike`: `mode = "any", classes = { "sword" }, allowUnarmed = false` — this is a deliberate,
  visible behavior change from Phase B. `TripleStrike` was previously usable both armed and unarmed
  (Phase B's regression baseline says so explicitly). It is now the sword-only skill that makes exit
  criterion 3's `wrong_weapon_class` rejection demonstrable at all in this repo (given the dagger/wand
  content gap above). Exit criterion 7's regression check for `TripleStrike` should now read "rejects
  cleanly while unarmed or with a non-sword weapon, works with a sword equipped" rather than "works
  unconditionally like Phase B."
- `Dash`, `DodgeRoll`, `ManaBall`, `CascadingManaBalls`, `Punch`, `SinglePunch`: left without a
  `requirements` field (ungated), since none of them are weapon-conditional skills.

## Phase D — authoring enums and projectile basic attacks

Two things Phase C left open: item authoring was entirely untyped strings, and there was no way for a
basic attack to do anything but sweep a cone.

### D11. Enums back every closed-set authoring field

Equipment definitions are mostly string fields, and a mistyped string was never an error — it was a
silent fallback. `class = "swrod"` resolves no basic attack profile and degrades to unarmed;
`affixContext = "sheild"` rolls nothing but `any` affixes forever. Both failures look like the system
being broken rather than the content being wrong.

`ItemTypes.luau` now declares closed string unions (`EquipSlot`, `EquipmentClass`, `WeaponClass`,
`DamageType`, `AffixContext`, `ItemTag`, `ProjectileMovementType`) and `ItemEnums.luau` holds the
matching runtime constant tables, following the existing `StatTypes.StaticStats` pattern. Authoring
reads `class = ItemEnums.WeaponClass.Wand`.

Three consequences worth recording:

- **Collection fields are typed as `{ ItemTag }` / `{ EquipSlot }`, not `{ string }`.** Luau checks
  array types invariantly, so with `{ string }` fields an inline `tags = { ItemEnums.Tag.Ranged }`
  infers as `{ ItemTag }` and is then *rejected* — which would force every item file to launder its
  lists through annotated locals. Typing the field as the union is what keeps authoring inline. The
  helpers that consume these lists (`hasTag`, `contains`, `containsString`) took the union element
  type to match.
- **The validator checks enum membership too, not just the type checker.** Item defs reach the
  Registry via `require`, so a def authored without `ItemEnums` (or with an `:: any` anywhere in the
  chain) can still carry a value the union would have rejected. The type checker is fast feedback;
  the validator is the guarantee.
- **`EquipmentSlotSchema` no longer declares its own slot union** — it re-exports `ItemTypes.EquipSlot`
  and keeps only display order, with a startup assert that every enum slot has an order entry. Two
  slot lists that could drift was exactly the class of bug this phase closes.

### D12. The weapon owns the projectile; the profile owns whether a step fires one

The same split D7 draws for damage: the weapon says *what*, the profile says *when*.

- `WeaponConfig.projectile` (`WeaponProjectileConfig`) declares the template, muzzle, speed,
  lifetime and flight.
- `BasicAttackStepSpec.delivery` (`"cone"` | `"projectile"`, nil means cone) declares that a step
  fires one.

This is what lets one `wand_light_1h` profile serve a plain wand, a flame wand and a frost wand. Each
declares its own `damage[].type` and its own `templateKey`; neither needs a profile, a skill, or a
line of code. Putting the projectile on the *profile* instead would force `wand_fire_basic`,
`wand_frost_basic`, … — Guardrail 8's "a skill per weapon type" problem reappearing one level down.

The damage path needed no work at all. Both delivery branches receive the identical `scaled` typed
damage list, so a Fire wand deals Fire because D7 already carries weapon damage types end to end.

### D13. Muzzle gives position; the cursor gives direction

Two different sources, for two different reasons.

**Position** comes from `WeaponProjectileConfig.muzzleSocket`, an Attachment on the weapon's own
asset (same namespace as a visual profile's `assetSocket`), so the bolt leaves the wand tip rather
than the player's chest. Server-side `EquipmentVisualService` holds the real welded weapon model, so
this is readable at fire time; it gained `getVisual` / `getSocketCFrame` for that. The attachment's
**rotation is ignored** — it only has to sit in the right place.

**Direction** comes from the player's aim, captured on the client at the moment of activation and
sent as `aimPoint` on the skill request. Muzzle orientation is not usable as an aim vector: it is
whatever the artist gave the attachment, rotated by whatever the hold animation is doing that frame.

Three details that matter:

- **An aim *point*, not a direction.** The muzzle sits most of a character's width off the camera
  axis, so a bolt fired parallel to the camera ray drifts wider the further it travels and misses
  what the cursor was over. Aiming muzzle→point converges at every range. The client raycasts the
  cursor ray into the world (or takes a far point along it against open sky) and sends the result.
- **Sampled at activation, not at release.** Projectiles leave partway through the cast animation
  (`hitDelays`). `BasicAttack` holds the activating request data so the shot goes where the player
  was pointing when they pressed, not wherever the camera has swung during the wind-up.
- **Aim is untrusted input** and `BaseSkill:resolveAimDirection` rejects wrong types, NaN and absurd
  distances. Worth being clear that a *plausible* but dishonest aim point is not a meaningful exploit
  — a player can already turn to face any direction instantly, so free aim grants nothing that
  turning does not. The validation is about malformed data, not advantage.

Falling back to the caster's facing when there is no aim is what makes this work for NPCs, which cast
`BasicAttack` server-side with no client and turn to face their target anyway.

There is deliberately **no root-relative fallback muzzle offset**. A guessed muzzle is a bug that
looks like a feature. If the attachment is missing, the step warns and degrades to the profile's
`hitCone`, and `EquipmentAuthoringValidator` reports it at startup against the actual asset.

For the same reason `launchSpeed` and `lifetime` are **required** on `WeaponProjectileConfig`: how
fast a bolt flies and how long it lives are properties of the weapon, not of the attack firing it, so
no skill-side constant stands in for them.

### D14. A shield is an offhand, not armour

`RoundShield` was authored as `slots = { "Body" }, class = "shield"` with no `offhand` block. That is
inert in combat: `CombatLoadoutResolver.resolveSlot` finds neither a weapon nor an offhand config and
returns nil, so the slot reads as empty to every combat system while still looking equipped, and
`modes.canBlock` never becomes true.

The shape is: `slots = { Secondary }`, `class = "offhand"`, plus an `offhand` block declaring
`type = "shield"` and `blockProvider = true`. The validator now errors on any offhand item that is not
Secondary-slottable.

### D15. Affix eligibility is by declared context; `any` is a declaration, not a fallback

A wand was rolling `+2 Physical Damage` and `+2 Armor`. Two compounding causes:

1. **Every affix was eligible for every item.** `rollKind` picked from the whole prefix/suffix pool by
   weight with no filtering, so an armour prefix could land on a weapon.
2. **`any` was a catch-all fallback.** When the picked affix declared nothing for the item's context,
   `resolveModifierDefs` silently fell back to its `any` bucket. Fury's `any` was `PhysicalDamage`;
   Sentinel's was `Armor`.

Worse, Fury's `any` PhysicalDamage carried **no `scope = "weapon"`** unlike its `melee_weapon`
entries, so it projected into global player stats — the Guardrail 7 leak again, arriving through the
fallback path rather than the authored one.

The model is now: **an affix can roll on an item only if it declares modifiers for that item's
context.** `AffixRegistry.listByKindForContext` filters the pool up front, and `pickTier` filters
tiers the same way so an eligible affix cannot pick a tier that grants it nothing. `any` still
exists, but now means "explicitly applies to every item" (OfVigor's flat Health) rather than "what to
use when this affix forgot about your item".

Consequence for authoring: **a lazy `any` bucket makes an affix eligible everywhere.** Fury and
Sentinel had theirs removed; Scholar and OfTheFairy gained real `magic_weapon` pools so wands roll
weapon-scoped MagicDamage and crit instead of inheriting someone else's leftovers.

The validator gained the rule that closes this class: **a weapon-local target may not appear in an
`any` bucket at all.** It is wrong in both directions there — unscoped it leaks globally when it
lands on a weapon, scoped it does nothing when it lands on armour. The pre-existing weapon-scope
check missed this because it keyed on the context name containing "weapon", and `any` does not.

### Phase D status: IMPLEMENTED — NOT Studio-verified

Type-clean (per-file LSP diagnostics, 2026-07-30). Nothing in this phase has been run.

**Content requirement:** `CrookedWand`'s asset needs a `Muzzle` Attachment at the wand tip. Position
only — its rotation is irrelevant. Until it exists the validator errors at startup and wand basic
attacks degrade to a cone with a warn. This is by design — see D13.

Also unverified, carried over from Phase C: D10's two-handed auto-unequip still has no two-handed
weapon to exercise it, and it is the only part of this refactor that mutates inventory.

### Phase D exit criteria — verify in Studio

1. Startup validator is clean apart from the known `Muzzle` error, and *that* error names the asset
   and attachment.
2. Equipping `CrookedWand` resolves `wand_light_1h`; basic attack fires a bolt **from the wand tip**
   that flies **toward the cursor**, including when the cursor is well off the character's facing.
3. That bolt deals **Magic** damage, not Physical — the D7/D12 payoff.
4. Equipping `IronDagger` resolves `dagger_light_1h` (previously it warned and fell back to unarmed).
5. `RoundShield` equips into Secondary, is rejected from Body, and sets `modes.canBlock`.
6. A shield in Secondary plus a sword in Main does not read as dual wield.
7. Regression: sword and unarmed basic attacks behave exactly as they did in Phase C.

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
- [x] Remove legacy fields from migrated defs (`IronSword`, `LeatherChest` are clean).
- [ ] Remove fallback logic once all equipment defs use explicit config.
  - `EquipmentDefUtils.getBaseModifiers` still has a `def.baseStats` path
  - `getEquipSlots` / `getRequirements` still fall back to top-level fields
- [ ] Stop deriving affix context from tags/slots after all equipment defs declare it.

### Phase 4: Item Content Packages
- [x] Decide package folder layout.
- [x] Support package-local item defs.
- [x] Support package-local single-use visual profiles.
- [ ] Keep shared visual profiles for reusable or rig-specific appearances.
- [x] Migrate first equipment packages: `IronSword`, `LeatherChest`.

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

### Phase 8: Weapon / Offhand Data Contracts
- [x] Add `WeaponConfig`, `OffhandConfig`, `WeaponDamageRoll`, and `CombatLoadoutSnapshot` shared types.
- [x] Move weapon damage/speed/range out of projected `baseRolls`.
- [x] Update `IronSword` to use `equipment.weapon`.
- [x] Add authoring validation for weapon class, handedness, allowed slots, damage ranges, and attack speed.
- [x] Add modifier scope support for `global`, `attribute`, `weapon`, and `skill`. *(Phase A1 — verified in Studio)*
  - `ModifierEntry` and `AffixModifierRollDef` carry `scope`; both roll paths propagate it
  - `CapabilityResolver` projects only `global`/`attribute`; `CombatLoadoutResolver` folds `weapon`-scoped entries into the weapon itself
  - `Fury` / `OfTheFairy` weapon-context entries marked `scope = "weapon"`
  - Guardrail 7 now actually enforced: a magic sword's `+2 Physical Damage` applies while armed and disappears on unequip

### Phase 9: Hard Equip Validation
- [x] Add server-side equipment requirement validation before slot mutation.
- [x] Reject failed stat/attribute requirements instead of equipping suppressed gear.
- [x] Validate slot compatibility and secondary-slot item type.
- [x] Validate two-handed/offhand conflicts.
- [x] Return structured equip error reasons to the client.
- [ ] Level requirements are **deferred**, not pending — no progression system exists. See D5.

### Phase 10: Combat Loadout Runtime
- [x] Add `CombatLoadoutResolver`.
- [x] Add `CombatLoadoutService`.
- [x] Recompute combat loadout after equip/unequip.
- [x] Replicate combat loadout snapshots to the client.
- [x] Add client mirror for UI and local preflight only.
- [x] **Consumers exist.** *(Phase A3/A4 — verified in Studio)* `BaseSkill:resolveWeaponDamage` reads the snapshot for damage; `SkillTimingService` reads main-hand `attackSpeed` for tempo; client prediction reads `CombatLoadoutMirror`. The pipeline is no longer inert.

### Phase 11: Skill Requirement Gate → Phase C
- [ ] Add skill requirement schema.
- [ ] Add server authoritative skill requirement validation.
- [ ] Add client-side preflight using mirrored combat loadout.
- [ ] Add structured rejection reasons for wrong weapon/offhand/loadout.

### Phase 12: Adaptive BasicAttack → Phase B — COMPLETE, verified in Studio
- [x] Add `BasicAttackProfileRegistry`.
- [x] Add `unarmed_basic` profile.
- [x] Add `sword_light_1h` profile.
- [x] Replace default offensive `Punch` usage with adaptive `BasicAttack`.
- [x] Keep `Punch` only as temporary migration content or unarmed profile implementation detail.
      (Still live for NPCs via the Goblin spec — do not delete until NPCs migrate.)
- [x] Resolve weapon-local damage/speed during attack execution. Damage is typed end to end (D7).

### Phase 13: Dual Wield Resolution → Phase C
- [ ] Implement deterministic hand candidate resolution.
- [ ] Alternate valid hands for generic adaptive attacks.
- [ ] Support explicit `main`, `secondary`, and `both` profile steps.
- [ ] Ensure mixed loadouts like dagger + wand do not break skill resolution.
- [ ] Add tests for sword+sword, sword+shield, bow+quiver, dagger+wand, and invalid loadouts.

## Guardrails

1. Do not expand the old top-level `visuals` format.
2. Do not add more affixes to the monolithic registry.
3. Keep fixed base item level as authored content, not mutable progression.
4. Make generation server-owned.
5. Keep crafting optional and readable.
6. Prefer explicit authoring and validation over inferred behavior.
7. Do not project weapon base damage/speed into global stats.
8. Do not create separate required basic skills for every weapon type.
9. Keep dual wield resolver permissive but deterministic.
10. Server remains authoritative for equip validation and skill loadout validation.
11. Do not build infrastructure without a consumer in the same slice. Phases 1-10 produced a complete, inert weapon pipeline; that is the failure mode this guardrail exists to prevent.
