# Progression Launch Content — first draft

Status: **starting point, drafted 2026-10-26.** Something concrete to build and playtest against,
not a finished design: names, numbers and whole nodes are expected to change as progression content
gets more thought. The rules it follows live in `progression-direction.md`.

## Conventions

**Node kinds.** `Form` (a shape: how the basic attack is delivered), `Infusion` (what it carries),
`Passive` (always on), `Select` (selectable passive, one of N from a shared pool), `Attuned`
(attunement-only, element trees).

**Ranks.** Each branch (and trunk) unlocks nodes at branch-XP thresholds, written here as ranks
R1–R4. A branch keeps earning past its last node while its scaling grows, then is Mastered. The XP
behind each rank is not set yet.

**Attribute requirements** are written Low / Mid / High. Attributes start at 0 and the points per
level are not designed yet, so these become numbers once that budget exists.

**Weapon contexts at launch.** A form lists the contexts it fits.

| Context | Track of its default form | Exists today |
|---|---|---|
| unarmed | Blunt (Punches) | yes |
| sword (one-handed blade) | Blade | yes |
| dagger | Blade | yes |
| dual daggers | Blade | yes (dual-wield exists) |
| greatsword (two-handed blade) | Blade | no |
| mace (one-handed blunt) | Blunt | no |
| hammer (two-handed blunt) | Blunt | no |
| wand | Magic | yes |
| staff (two-handed magic) | Magic | no |
| bow | Ranged | no |

A weapon whose default form the character cannot use (a wand without the Intelligence for Mana
Ball) falls back to a physical swing with an existing swing animation.

## Attack-type trees

Every tree has the same frame: a trunk with the root form and two passives, two branches of four
ranks, and a joining form that needs rank 3 in both branches. That is 13 nodes, two of them
selectable passives.

### Magic — contexts: unarmed, wand, staff

| Where | Node | Kind | Fits | Needs | Effect |
|---|---|---|---|---|---|
| Trunk | **Mana Ball** | Form (root) | all | Int Low | Slow orb, 3 steps. Today's `wand_light_1h` ("Mana Bolt") becomes this. |
| Trunk | Arcane Focus | Passive | | | Increased magic damage. |
| Trunk | Mana Flow | Passive | | | Forms cost less mana. |
| Focus R1 | **Mana Bolt** | Form | all | Int Low | Fast narrow bolt; fewer, harder hits. |
| Focus R2 | Concentration | Passive | | | Crit chance with magic projectiles. |
| Focus R3 | **Piercing Bolt** | Form | all | Int Mid | Passes through targets. |
| Focus R4 | Overcharge | Select | | | The last step of a magic combo hits much harder and costs more mana. |
| Area R1 | **Mana Burst** | Form | all | Int Low | Short-range blast in front of the caster. |
| Area R2 | Resonance | Passive | | | Increased area of effect. |
| Area R3 | **Scatter** | Form | wand, staff | Int Mid | The orb splits into three. |
| Area R4 | Volatile Mana | Select | | | Magic area hits leave a brief damaging field. |
| Join | **Mana Comet** | Form | all | Int High | A heavy bolt that bursts in a small area on impact. |

### Blade — contexts: sword, dagger, dual daggers, greatsword

Branches suit weapon types without locking them: Weight favours heavy blades, Edge favours light
ones, and each has a form only one context can use.

| Where | Node | Kind | Fits | Needs | Effect |
|---|---|---|---|---|---|
| Trunk | **Strike** | Form (root) | all | — | The basic blade combo, animated per weapon. Today's `sword_light_1h` ("Slash") and `dagger_light_1h` ("Stab") are its sword and dagger variants. |
| Trunk | Honed Edge | Passive | | | Increased physical damage with blades. |
| Trunk | Footwork | Passive | | | Move faster during a combo. |
| Weight R1 | **Wide Slash** | Form | sword, greatsword | Str Low | Broad arcs; hits several enemies. |
| Weight R2 | Heft | Passive | | | More stagger and knockback with blades. |
| Weight R3 | **Cleave** | Form | greatsword | Str Mid | Two slow, heavy steps; the second hits a small area. |
| Weight R4 | Momentum | Select | sword, greatsword | | Each step of a combo deals more than the last. |
| Edge R1 | **Flurry** | Form | sword, dagger | Dex Low | Five quick, light steps. |
| Edge R2 | Quick Hands | Passive | | | Increased attack speed with blades. |
| Edge R3 | **Twin Fangs** | Form | dual daggers | Dex Mid | Alternating-hand combo; the hand alternation already exists. |
| Edge R4 | Bloodletting | Select | | | Blade hits can cause bleeding. |
| Join | **Dancing Steel** | Form | all | Str Mid, Dex Mid | Quick steps into a heavy finisher with knockback. |

### Blunt — contexts: unarmed, mace, hammer

| Where | Node | Kind | Fits | Needs | Effect |
|---|---|---|---|---|---|
| Trunk | **Punches / Bash** | Form (root) | all | — | Today's `unarmed_basic` ("Punches"); a mace or hammer bashes instead. |
| Trunk | Concussive | Passive | | | More stagger with blunt hits. |
| Trunk | Solid Stance | Passive | | | Knocked back less. |
| Brawler R1 | **Rapid Jabs** | Form | unarmed | Dex Low | Exists today (`unarmed_rapid_jabs`). |
| Brawler R2 | Combo Flow | Passive | | | Increased attack speed unarmed. |
| Brawler R3 | **Iron Rush** | Form | unarmed | Dex Mid | Five-hit rush ending in an uppercut that knocks back. |
| Brawler R4 | Second Wind | Select | unarmed | | Landing a full combo restores stamina. |
| Crusher R1 | **Overhead Smash** | Form | mace, hammer | Str Low | Slow, heavy downward blows. |
| Crusher R2 | Armor Break | Passive | | | Blunt hits briefly lower the target's armor. |
| Crusher R3 | **Ground Slam** | Form | hammer | Str Mid | The finisher strikes a ring around the impact. |
| Crusher R4 | Daze | Select | mace, hammer | | Heavy hits can stun briefly. |
| Join | **Earthshaker** | Form | all | Str Mid, Def Low | A stomp that staggers nearby enemies, then two heavy strikes. |

### Ranged — contexts: bow

| Where | Node | Kind | Fits | Needs | Effect |
|---|---|---|---|---|---|
| Trunk | **Shot** | Form (root) | bow | Dex Low | A plain arrow per step. |
| Trunk | Steady Aim | Passive | | | Faster, straighter arrows. |
| Trunk | Light Quiver | Passive | | | Forms cost less stamina. |
| Precision R1 | **Aimed Shot** | Form | bow | Dex Low | Hold to draw for more damage. |
| Precision R2 | Keen Eye | Passive | | | Crit chance with bows. |
| Precision R3 | **Piercing Arrow** | Form | bow | Dex Mid | Passes through targets. |
| Precision R4 | Weak Point | Select | | | Crits against distant targets deal more. |
| Volley R1 | **Split Shot** | Form | bow | Dex Low | Three arrows in a spread. |
| Volley R2 | Quick Draw | Passive | | | Increased attack speed with bows. |
| Volley R3 | **Arrow Rain** | Form | bow | Dex Mid | A lobbed volley onto the aimed point. |
| Volley R4 | Pin Down | Select | | | Volley hits slow enemies. |
| Join | **Barrage** | Form | bow | Dex High, Per Low | A rapid stream of arrows. |

## Element trees

Same frame, with infusions in place of forms and an attunement-only node at the end. Following the
content rules: only that element's own stats, its resistance capped low, no cross-element bonuses.
Attuning the element multiplies its tree's stats (≈ ×1.5, to tune). An infusion can be selected
without attuning the element, just weaker.

### Fire

| Where | Node | Kind | Needs | Effect |
|---|---|---|---|---|
| Trunk | **Fire I** | Infusion (root) | — | Part of the damage becomes fire; effects take its colour. |
| Trunk | Heat | Passive | | Increased fire damage. |
| Trunk | Fire Ward | Passive | | Fire resistance (capped tree share). |
| Reach R1 | **Fire II** | Infusion | | More conversion; flames extend slashes and bolts. |
| Reach R2 | Searing | Passive | | Fire penetration. |
| Reach R3 | Flame Reach | Passive | | Fire forms reach further, growing with Fire mastery. |
| Reach R4 | Blaze | Select | | Fire crits always ignite. |
| Spread R1 | Ignite | Passive | | Fire hits can burn. |
| Spread R2 | Lingering Burn | Passive | | Burns last longer. |
| Spread R3 | Cinders | Passive | | Burning enemies splash fire when they die. |
| Spread R4 | Wildfire | Select | | Burns spread to a nearby enemy on a kill. |
| Join | **Fire III** | Infusion | | Full conversion; opens Fireball and Fire Crescent. |
| End | Kindled Soul | Attuned | Fire attuned | Burns stack once more, and more fire damage. |

### Frost

| Where | Node | Kind | Needs | Effect |
|---|---|---|---|---|
| Trunk | **Frost I** | Infusion (root) | — | Part of the damage becomes frost. |
| Trunk | Cold | Passive | | Increased frost damage. |
| Trunk | Frost Ward | Passive | | Frost resistance (capped tree share). |
| Bite R1 | **Frost II** | Infusion | | More conversion; hits splinter into small shards. |
| Bite R2 | Frostbite | Passive | | Frost penetration. |
| Bite R3 | Brittle | Passive | | Frost crits deal more against chilled enemies. |
| Bite R4 | Shatter | Select | | Killing a frozen enemy bursts it into ice. |
| Grip R1 | Chill | Passive | | Frost hits slow. |
| Grip R2 | Deep Chill | Passive | | Chill is stronger and lasts longer. |
| Grip R3 | Freeze | Passive | | Fully chilled enemies freeze briefly. |
| Grip R4 | Permafrost | Select | | Frost area hits leave chilling ground. |
| Join | **Frost III** | Infusion | | Full conversion; opens Ice Lance and Frost Nova. |
| End | Heart of Winter | Attuned | Frost attuned | Freezes last longer, and more frost damage. |

## Named combinations at launch

Every shape works with every infusion by the generic rule; these pairings get their own identity:

| Shape + Infusion | Becomes |
|---|---|
| Piercing Bolt + Fire II | **Fire Bolt** — its own projectile |
| Mana Ball + Fire III | **Fireball** — explodes on impact |
| Wide Slash + Fire III | **Fire Crescent** — a crescent leaves the swing; reach grows with Fire |
| Piercing Bolt + Frost II | **Ice Lance** — pierces and chills everything it passes |
| Mana Burst + Frost III | **Frost Nova** — a freezing ring around the caster |
| Ground Slam + Frost III | **Glacial Slam** — the ring freezes the ground |
| Arrow Rain + Fire III | **Firestorm** — burning arrows on the area |

## Classes

Classes are rules matched against masteries: attuned attack-type level, element levels, and where
it adds flavour the leading attribute and furthest branch. The System offers; the player accepts at
a place in the world, often after a trial. One class at a time.

### Tier 1 — around character level 10

One per attack type, so every player is offered something. Needs that track attuned at level 5.
Trial: defeat a set of enemies with that kind of attack.

| Class | Rule | Gives (direction) |
|---|---|---|
| Swordsman | Blade attuned ≥ 5 | Blade damage, stamina. |
| Mage | Magic attuned ≥ 5 | Magic damage, mana. |
| Brawler | Blunt attuned ≥ 5 | Stagger, life. |
| Archer | Ranged attuned ≥ 5 | Projectile damage, move speed while shooting. |

### Tier 2 — around character level 30

Specialisations and hybrids. A player matching none is offered their tier 1 class's evolution
instead (Swordsman → Blademaster), so nobody is left without an offer.

| Class | Rule | Gives (direction) | Trial idea |
|---|---|---|---|
| Berserker | Blade ≥ 15, Strength leads, Weight furthest | Damage rises as life falls. | Win a fight against a pack under a time limit. |
| Duelist | Blade ≥ 15, Dexterity leads, Edge furthest | Crits after dodging. | Defeat an elite without being hit more than N times. |
| Spellblade | Blade ≥ 15 and Magic ≥ 15, both attuned | Blade hits restore mana; spells sharpen the next strike. | |
| Flame Knight | Blade ≥ 15, Fire ≥ 15 | Fire blade forms, burning enemies stagger more. | |
| Pyromancer | Magic ≥ 15, Fire ≥ 15 | Bigger burns, fire area. | |
| Cryomancer | Magic ≥ 15, Frost ≥ 15 | Longer freezes, chill spreads. | |
| Elementalist | Magic ≥ 20, Fire ≥ 20, Frost ≥ 20 | +10% elemental damage; cross-element synergies (fire hits on chilled enemies, frost hits on burning ones). | Defeat enemies that resist one element, using the other. |
| Guardian | Blunt ≥ 15, Defense leads, Crusher furthest | Armor, taunt-like threat, ally protection. | Defend an NPC from waves of enemies. |
| Martial Artist | Blunt ≥ 15, Dexterity leads, Brawler furthest | Unarmed attack speed, evasion. | |
| Hunter | Ranged ≥ 15, Perception leads, Precision furthest | Crits on marked targets, reveals enemies. | Track and defeat a specific elite in a map. |

### Tier 3 — later

Evolutions of tier 2, around character level 60. Not designed yet.

## Milestones

Placeholder levels, to tune with pacing:

| Character level | Unlock |
|---|---|
| ~3 | First attunement slot (an early shrine, part of onboarding). Until then only root forms are in use, which work unattuned anyway. |
| ~5–10 | Second attunement slot — soon, but not handed out with the first; exact level follows pacing. |
| ~10 | Tier 1 class offer. One selectable passive slot. |
| ~25 | Second selectable passive slot. |
| ~30 | Tier 2 class offer. |
| ~50 | Third selectable passive slot. |
| ~60 | Tier 3 class offer. |

## What this means for the code

- The mastery tracks in code (`shared/progression/MasteryTracks`: Unarmed, Sword, Dagger, Wand) become
  Magic, Blade, Blunt, Ranged, Fire, Frost. Track ids are save keys: rename before real players
  have saves.
- The five existing profiles map onto the trees: `unarmed_basic` (Blunt root), `unarmed_rapid_jabs`
  (Blunt, Brawler R1), `sword_light_1h` and `dagger_light_1h` (Blade root variants),
  `wand_light_1h` (Magic root, renamed Mana Ball).
- Profiles today belong to one weapon class (`weaponClasses`, `shapeFor`); they need a context list
  and attribute requirements, and selection is remembered per context (today per class key).
- New contexts (greatsword, mace, hammer, staff, bow) each need items, a profile and animations.
