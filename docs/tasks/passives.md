# Passives, Enemy Values & Second Cost Resource

## Goal

Asked for on 2026-10-27:

1. Make passive nodes do something, with a system that can express whatever a passive node might
   want to do, and new status effects where nodes need them.
2. Let forms cost a second resource (an infused punch spends stamina and a little mana).
3. Let the XP system take real enemy values: area level × enemy type × rank, instead of per-spec
   placeholders.

## Current decisions

### Passives (`server/Progression/Passives`, `shared/progression/NodeEffects`)

1. **Effects are data.** `NodeEffects` lists the effects of every passive, selectable passive and
   attunement-only node as `{ kind = ..., when = ... }` records.
   - It checks at load that every such node has effects, and that no other node does.
   - PassiveService checks at load that every `kind` used has an implementation.
2. **Kinds are code, one module each** (`Passives/Kinds`). A kind implements only the moments it
   acts in:

   | Moment | When it runs |
   |---|---|
   | `apply` | Ahead of time, on every recompute |
   | `outgoing` / `incoming` | An attack about to land: the attacker's effects, then the target's |
   | `afterHit` | A direct hit after it has landed |
   | `onKill` | An NPC the entity killed |
   | `onUse` | A paid skill use |

   A new behaviour is a new kind module, one-offs included. Kinds at launch:

   | Kind | Does | Used by |
   |---|---|---|
   | `stat` | Stat modifier while held context matches | Quick Hands, Combo Flow, Quick Draw, Searing, Frostbite |
   | `resistance` | Element resistance, capped per element (15, 20 attuned) | Fire Ward, Frost Ward |
   | `cost` | Skill cost in one resource ± share | Mana Flow, Light Quiver, Overcharge |
   | `damage` | Increased damage per packet, additive; `perComboStep` | Arcane Focus, Honed Edge, Heat, Cold, Momentum, Overcharge, Kindled Soul, Heart of Winter |
   | `damageTaken` | Reduced damage taken | (none yet) |
   | `critChance`, `critDamage` | Per-packet crit bonuses for matching hits | Concentration, Keen Eye, Weak Point, Brittle |
   | `knockback`, `stagger` | Dealt and taken | Heft, Concussive, Solid Stance |
   | `onHit` | Apply a status; parameters from fixed values or from the damage dealt; per-target cooldown | Ignite, Blaze, Chill, Freeze, Bloodletting, Armor Break, Daze, Pin Down |
   | `statusBoost` | The source's statuses last longer, are stronger, or stack higher | Lingering Burn, Deep Chill, Kindled Soul, Heart of Winter |
   | `onKill` | `explode` (share of the dead enemy's max health, as an element) or `spread` (pass a status on) | Cinders, Shatter, Wildfire |
   | `restore` | Resource back on a matching hit, once per moment | Second Wind |
   | `moveSpeed` | Always, or for a window after a skill use | Footwork |
   | `area`, `reach`, `projectileSpeed` | Numbers skills read (`PassiveQuery`) | Resonance, Flame Reach, Steady Aim |
   | `field` | Ground patch that damages or applies a status for a while | Volatile Mana, Permafrost |

3. **Filters (`when`).** One matcher (`Passives/Filters`) for every kind.
   - It can test the held context, the form's infusion, the attack's track, skill, delivery and combo
     step ("final"), crit (by damage type), the target's statuses and stacks, and distance.
   - Packet kinds read `damageTypes` per packet; after-hit kinds read what the hit dealt.
4. **Which nodes are in effect** is derived, like unlocks:
   - unlocked, and active (attack-type tracks need attunement);
   - selectable passives must also be chosen and have a slot.

   Recomputed on mastery progress (`MasteryService.onProgressChanged`), attunement, level-ups,
   selection, and combat loadout changes. The loadout recompute is also what applies a joining
   player's passives once their stats exist.
5. **Growth inside a node.**
   - Magnitudes scale by up to +50% (`NodeEffects.GROWTH`) as the node's branch runs from the node's
     threshold to Mastered. Join and end nodes follow the slower of the two branches.
   - An attuned element's tree is ×1.5.
   - Chances, durations given in seconds, and thresholds don't grow.
6. **Selectable passives.**
   - One shared pool. Slots open at character levels 10, 25 and 50 (`PassivePool`; placeholders).
   - The choice is saved as `progression.passives` and cut to the slots the level allows.
   - The request is `ProgressionSelectPassive { nodeId, selected }`.
   - In the canvas, clicking a selectable node toggles it. "NO FREE SLOT · NEXT AT LV 10" says why
     one can't be chosen.
7. **Only direct hits trigger after-hit effects.** A status's own damage (a burn's tick, which
   carries `metadata.effectId`) doesn't. Otherwise a fire tick could ignite and a burn would feed
   itself. Ticks still count as the last hit for kill credit, and outgoing damage passives such as
   Heat still scale them.
8. **Kill credit** goes to whoever hit last within 10 seconds. A dead NPC's statuses are cleared
   just after the death listeners run, so kill effects still see them.

### Combat changes the system needed (`CombatService`)

- **Attack hooks.** `addAttackHook` lets systems change an attack per target without the skills
  knowing about them. Packets are copied per target, so a change aimed at one target never leaks to
  the next.
- **Elements are resisted, not armoured.** `FireResistance` and `FrostResistance` are percentage
  points, capped at 75. They are reduced by `FirePenetration` / `FrostPenetration` and per-packet
  `resistancePenetration`, never below zero. Armor now applies only to non-element damage. That
  makes converting to an element a real choice against armoured enemies.
- **Crits and stagger.**
  - Per-packet `critChanceBonus` and `critDamageBonus`.
  - `critTypes` in the server result.
  - `AttackResult.crit` now reflects packet crits, so damage numbers show "!" for crits from the
    crit stat. It used to only reflect `metadata.isCrit`.
  - `metadata.staggerScale`.
- **Delivery.** `AttackMetadata.delivery` ("melee", "projectile", "area") is set by BasicAttack,
  ManaBall, CascadingManaBalls and TripleStrike, for filters. Passive damage uses "burst" and
  "field", so it can't set off area passives and chain.

### New status effects (`server/StatusEffects/Ailments`)

| Effect | Does |
|---|---|
| **Chill** | Up to 5 stacks, 8% slow each, at most 50% |
| **Freeze** | Stun-like, and the body stops |
| **Bleed** | Physical damage over time, like Burn |
| **Sunder** | Armor −25% while it lasts |
| **Slow** | A plain slow |

- Definitions can declare `defaultParams` and `potencyKeys`, which `statusBoost` scales.
- An application may raise its stack cap through `params.maxStacks`.
- Slows go through **`server/Movement/SpeedModifiers`**:
  - multipliers by source, kept on the model as `SpeedScale`;
  - NPC Movement multiplies its walk and run speeds by it;
  - players are set from the place's walk speed.

### Second cost resource

- **Infusions now cost mana per step** (`infusion.cost = { resource = "Mana", perStep }`: I 2, II 3,
  III 4) instead of a share of the form's cost.
  - A form that already spends Mana (Mana Ball) adds it to its own cost.
  - Any other form (punches, swords) pays it as a second resource.
  - Named combinations keep a share surcharge on the main cost.
- **The cost pipeline is general.**
  - Any skill's `config.extraCosts` (`{ resource, steps | amount }`) is resolved through the same cost
    modifiers.
  - Every cost is checked together before any is taken.
  - Each cost is previewed in `SkillMetadata.extraCosts`, and `ClientStatsStore.canAfford` checks
    them on the client.

### Enemy values (`shared/progression/EnemyRewards`, `NPCSpawner`)

- **What a spec declares:** what the enemy is, `progression = { type = 1.5, mastery = ? }`.
- **What the spawn decides:** where and how strong.
  - `areaLevel` comes from the spawn options, else the nearest ancestor with an `AreaLevel`
    attribute (a map folder), else 1.
  - `rank` is forced by the map builder or rolled: Magic 12%, Elite 3%. Unique is never rolled.
- **The values** (placeholders):

  | Value | Formula |
  |---|---|
  | XP | `10 × level^1.25 × type × rank` |
  | Mastery value | `40 × level^1.15 × type × rank` |

  Rank factors follow Path of Exile's: XP ×3.5 Magic / ×8.5 Elite / ×5.5 Unique.
- **Overrides:** explicit `xp` / `masteryValue` in the spec or spawn options still win.
- **Respawns** keep the area level and a forced rank; a rolled rank rolls again.
- **Kill XP** takes a very light level-difference penalty: no loss within 3 + level/16 levels, then
  −4% per level, never below half.
- **Rank changes rewards only for now.** Rank-based stat bonuses for enemies are for the NPC pass.

## Validation results

Studio playtest over MCP, 2026-10-27:

| Check | Result |
|---|---|
| Enemy values | The Slime spawned with area 1, Normal, 10 XP, 40 mastery. After death it respawned in area 1 with the rank re-rolled. |
| `stat`, `resistance` | Fire Ward with a mastered trunk: Fire Resistance 12 (8 × 1.5). Searing: Fire Penetration 10. |
| `damage` | Heat +18% (12% × 1.5) on Fire packets only. Arcane Focus +10.8% on Magic (the save has Magic attuned, growth 1.083). Exact against an attack-hook trace. |
| `onHit`, `statusBoost` | Ignite started Burns ticking at 15.6% of the hit's Fire damage (12% × growth 1.1 × Heat). After the DoT fix, no secondary burns from ticks. |
| Chill, Deep Chill, Freeze | The dummy's speed went 1 → 0.89 → 0.77 → 0.66 → 0.54 (≈11.4% per stack with Deep Chill). At 5 stacks it froze to 0 for 1 s, then held at 0.43. |
| `onKill` (Cinders) | A Slime that died burning exploded: the dummy beside it took 25.96 Fire from "Passive" (10% of 220 × Heat). |
| Second resource | Unarmed with Fire I: metadata carries an extra Mana cost per step, reduced by Mana Flow (1.68 rather than 2). With Mana drained, the punch was refused locally (`insufficient_resources`) with full stamina. |
| Selectable pool | At level 5: Blaze refused `no_free_slot`; Wildfire `locked`; Heat `unknown_passive`; dropping works. |
| Canvas | Passives read PASSIVE, Blaze AVAILABLE, Wildfire its requirement. |

The dev save was put back afterwards:
- Fire trunk 22.38, branches 0; Frost 0;
- no infusion and no passives chosen;
- wand in hand; slot set 2.

Magic kept the trunk XP the test swings earned.

## Notes

- **Not exercised in play:**
  - choosing a selectable passive with a free slot (needs character level 10; the dev save is 5);
  - `spread` (Wildfire), `field` (Volatile Mana, Permafrost) and its disc;
  - `restore` (Second Wind), `moveSpeed` (Footwork), `knockback` / `stagger` magnitudes;
  - `critDamage`, and anything bow-only (no bows yet).

  All of them go through the same filters and hooks as the kinds that were verified.
- **Old demo modifiers removed.** InitDev used to register two demos from when the modifier system
  was first checked by hand: `TestModifiers` / `SampleModifiers` (30% Physical → Fire, Burn and
  Bleed chances, life drain on every attack) and `meleeDoubleCost` (melee stamina costs paid in Health
  at 1.5×). Both are gone, so combat in Studio is what the game does. The mana and health
  regeneration InitDev sets up stay.
- **Statuses on NPCs aren't shown on the client yet:** no burn or chill visual beyond damage numbers
  and the slow itself. Worth adding with the UI pass.
- **Slime melee reach:** the Slime's root sits low, so a punch aimed level often misses it. Worth a
  look in the NPC pass.
