# Progression Direction — masteries, attunement, classes, forms

Status: **direction agreed 2026-10-25; XP, tracks and branches revised 2026-10-26.** Build steps 1–3
are done, plus attunement and hard gear requirements (see "Build order"). Content (the actual masteries, trees, classes, numbers) and the
management space are still to be designed.

## What it has to achieve

- **Freedom first, identity later.** A player is not asked to pick a class before they know the game.
  They pick up whatever weapon and cast whatever they find, and their playstyle forms from what they
  actually do.
- **Off-spec is possible, not good.** A mage can pick up a sword and swing it. They are just far
  worse at it than at what they have been training.
- **No one character is everything.** Progress is never deleted, so the limit has to be on what is
  *active* at once, not on what has been earned.
- **A path, not a sandbox.** Freedom without direction confuses players. The game always shows a
  next goal.
- **No huge skill tree.** PoE's passive tree is the reference for what to avoid: too much to read for
  an impatient audience. Every tree a player sees is small.
- **A world, not a menu.** Rules have an in-world reason where possible.

## The model

Five layers, each simple on its own.

### 1. Character level

XP from everything raises the level; each level grants attribute points (`Strength`, `Defense`,
`Dexterity`, `Intelligence`, `Perception`). Attributes are a budget: a point in Intelligence is a
point not in Strength, which is the first, natural pressure toward a focus.

### 2. Masteries — grow by doing

A mastery is a progression track with its own level, raised by use. Two families (revised
2026-10-26):

- **Attack-type masteries — how you fight:** Magic, Blade, Blunt, Ranged. Not one per weapon: a mage
  does not need a wand to cast, and a bare-handed fireball is Magic. Blade covers swords and daggers;
  its branches suit weapon types implicitly (a heavier, slower path suits greatswords, a faster one
  daggers) without locking them. A skill feeds the track of what it does; a skill that needs a sword
  needs one equipped and feeds Blade. Shapes live in these trees.
- **Element masteries — what the attack carries:** Fire and Frost at launch (more later). An element is not tied to a
  weapon: fire mastery shapes a mage's bolt and a warrior's slash alike. Infusions live here. An
  element mastery's passives modify that element's stats, so they improve every skill that uses the
  element, not only forms; the selected infusion is what modifies the form.

Growth by use means a new player progresses visibly with zero decisions, and System notifications
("Wand Mastery 3") give the frequent, small rewards this audience needs.

### 3. Attunement — the limit on breadth

Only **attuned** masteries grant their forms, passives and bonuses.

- **One slot early, a second later. Two is the maximum** — more would make the conditional unlocks
  below too hard to follow.
- **Unattuned masteries keep all their progress.** Nothing is ever deleted. Re-attune and everything
  is back.
- **Attunement is changed at a specific place or NPC in the world**, not from a menu. It is part of
  the world's magic system, which gives the rule a reason to exist beyond balance.

This is the one rule a player needs to understand ("you can focus on two things"), and it bounds
power at any moment. Grinding every mastery on one character is allowed; using them all at once is
not. Swapping mid-fight is not possible.

**Revised 2026-10-26 — attunement works differently per family:**

- **Attack-type masteries need attunement.** Unattuned, they provide nothing — except the root form,
  which always works as the fallback, so anyone can still swing a sword.
- **Element masteries are always active; attunement strengthens them.** A full elemental build
  should not be an endgame goal gated behind many slots. One line for players: *weapon skills need
  attunement; elements always work, and attunement makes them stronger.*
- This keeps breadth horizontal, not vertical: an attack carries one element, so mastering Frost
  does nothing for a Fire attack, and someone with every element maxed has more options, not more
  power per attack. Element XP only comes from dealing that element, so breadth costs real time.
- **Content rules that keep it fair** (breadth only becomes power through these):
  1. Element trees modify only their own element (its damage, penetration, ailment chance and
     duration). No generic stats (max life, crit, cast speed, "+all damage") — those stack across
     elements and belong in attack-type trees and classes.
  2. Element trees may give resistance to their own element (the character grows used to it), but
     capped low — roughly 15–20% from the tree out of the overall cap, a little more when attuned —
     so gear stays the main source and a veteran with every element still needs it to reach the
     cap. The same small cap applies to defences against that element's ailments. Raising the
     maximum resistance never comes from trees, only from classes and unique gear. (Elemental
     resistance stats do not exist yet; `StatTypes` has only Armor.)
  3. Cross-element synergies ("+damage against chilled enemies") live only in classes.
  4. Late content is balanced assuming veterans have every element maxed.

- **Attuning an element** multiplies its tree's stats and opens an attunement-only node at the end of
  its tree. An infusion can be selected without attuning its element, just weaker.
- **Two slots at launch**, not handed out together: the first early (onboarding), the second soon
  after (around level 5–10, by pacing), with room for a third; the elemental mage no longer needs
  more.

### 4. Class — offered by the System, not picked

At milestones the System reads the attuned masteries and the leading attribute and offers a class:

> *The System has observed your affinity for Fire and the Wand. Class available: Pyromancer.*

- A class bundles passives, opens its own skill line, and **always presents one next goal** — the
  general path that freedom alone does not give.
- Classes evolve at later milestones.
- Hybrids come from mastery pairs (Fire + Sword → a flame knight). The class list is an authored
  table of combinations, so its size stays under control.
- A class does not own forms. It can gate higher infusion tiers or specific named combinations
  (below), which lets classes shape forms without duplicating them.

**Decided 2026-10-26:**

- **Class names are authored** behind combinations of masteries and level thresholds; attributes and
  branch choice can also distinguish classes, since masteries are broad.
- **The System offers; the player accepts in the world**, at a location, NPC or device. The offer
  is itself the next goal ("Class available: Pyromancer. Seek the Ember Shrine.") and stays pending
  until accepted.
- **A class can be reverted at a shrine for an even larger cost** than an attribute respec.
- **Accepting a class can take a trial**: early tiers are simple (defeat these enemies), later ones
  bespoke (a Guardian defends an NPC from waves). Trials are quests built from reusable objectives
  (kill N of a type in an area, survive waves, protect an NPC, beat a time limit), so they come from
  the quest system (`docs/planning/dialogue-and-quest-system.md`) rather than a system of their own.

**Proposed, not yet confirmed:**

- **A class is a rule matched against the masteries** (attuned attack types, element levels), not
  an entry in a table of exact pairs, so many combinations stay manageable. Attunement and track levels are the core of
  every rule; the leading attribute and furthest branch pick variants where that adds flavour.

  | Class | Matches when |
  |---|---|
  | Pyromancer | Fire attuned, Fire ≥ 10 |
  | Flame Knight | Blade + Fire attuned, both ≥ 15 |
  | Berserker | Blade ≥ 15, Strength leads, heavy branch furthest |
  | Elementalist | Fire + Frost (+ Lightning later) attuned, each ≥ 20 |

- **Combination rewards are what a class gives**, not a second list: the Elementalist grants
  +10% elemental damage; a fire + poison class grants ailment damage and duration. One class at a
  time; matching several rules means several offers, and choosing is the identity decision.
- Un-attuning a mastery the class needs makes the class dormant until re-attuned or changed.

### 5. Gear requirements — hard locks

*Revised 2026-10-27 (was: soft penalties).* Gear whose level or attribute requirements are not met
**cannot be equipped**, so trading a low-level character high-end gear cannot break progression.
Equipped gear that stops meeting them (the item lending the attributes came off, an attribute reset)
stays equipped but is **inactive**: it gives nothing, and a weapon fights as if unarmed, until they
are met again. Attributes from other gear count, never an item's own, so a ring can open a shield
but two items cannot open each other. Off-spec play stays possible through what a character can
equip and their low mastery (root form only, no bonuses).

## Experience

*Agreed 2026-10-26; the numbers are still to settle.*

Character XP and mastery XP are **two independent streams**. Neither draws from the other, so
training a weapon never costs character progress.

- **Character XP** comes from many sources: enemies, quests, bounties, looting, discovery. Quests and
  bounties are the big rewards. Proper level-by-level requirement scaling.
- **Mastery XP** comes from **use**, not kills, but **difficulty drives it**: harder fights give much
  more, and later requirements are high enough that only hard fights reach them in reasonable time.
- **Training is real but small.** An empty swing gives a little mastery XP — the character is
  practising — but it only matters for the first few levels. AFK swinging must never max a mastery.
- **No visible power number** of any kind. A hidden power estimate (from attributes, gear, nodes) was
  considered and shelved: gameable by unequipping gear, and nothing to calibrate it against yet. The
  character level is not a power number: the STATUS panel shows it, as it does today.

### Character XP from enemies

Modelled on Path of Exile, where every monster in an area shares the area's level and differs by type
and rarity:

- **A map has an area level; its enemies inherit it.** Map builders do not vary enemy levels to
  balance a map.
- **Each enemy type carries an XP multiplier** for what it actually is: a worm that spawns forty at a
  time is worth a fraction of a skeleton of the same level.
- **Ranks: Normal, Magic, Elite, Unique.** Rolled by chance per batch when the dungeon loads, and
  optionally forced by the map builder. A Unique is a very rare spawn under specific conditions in
  specific maps. Rank raises XP (PoE, for reference: magic +250%, rare +750%, unique +450%).
- **Bosses are dedicated entities**, never a promoted normal enemy, and use a type multiplier like
  everything else, so a higher-level run of a dungeon makes its boss worth more.
- Many kills per level, each giving a small amount. **Pacing: fast early (the hook), then mid and
  late levels that take real, dedicated effort**; tuned continuously.
- **Kill XP is shared by contribution.** With a very light level-difference penalty and level /
  mastery / attribute requirements on skills and gear, carrying cannot break progression.

### Mastery XP from use

- **The basic attack grows the branch of the selected focus** (form): with Piercing Bolt selected,
  basic attacks progress that branch.
- **Skills grant mastery by what they do**, from their data: an area skill grows the weapon's area
  branch even while the form's focus is piercing; a fire skill also grows Fire.
- **A skill's tier scales its mastery gain** (set in skill data): a late-game nuke teaches more per
  use than an early fireball.
- **A new track must not jump many levels at once**, even at endgame.
- **Each branch has its own XP.** XP always lands in a branch — the selected focus's for basic
  attacks, the matching branch for a skill, the track's shared trunk when nothing matches. The track
  level comes from total XP across branches on a curve (stable for requirements like "needs Blade
  12", independent of tree size); nodes unlock at branch-XP thresholds (a joining node needs both);
  continuous in-node scaling keys on branch XP. (Rejected: level = number of unlocked nodes, which
  ties the level to tree size and leaves nothing continuous to scale on.)
- **A branch's first rank unlocks from the trunk** (proposed while building, to confirm): XP only
  reaches a branch through a form selected in it or a skill tagged for it, so without this a branch
  whose first node is a form could never start.
- **Branches complete.** A branch (or trunk) runs a stretch past its last node while that form's
  scaling grows, then is **Mastered** and stops taking XP; nothing is redirected elsewhere, so focus
  still decides what grows. A track's level therefore has a natural maximum. The UI marks a mastered
  branch clearly, which doubles as a nudge toward the next branch or track.
- **Support skills (heals, buffs, shields) give no mastery XP.** They match no branch. A defence or
  shield track may come later if defensive content grows.
- **What a use earns:**
  - Any use: small flat XP. The training dummy gives a little more early on. Both only below a
    training cap.
  - A use that connects: the enemy's mastery value (area level × type × rank) × the share of its max
    HP removed, × the skill's tier. Damage beyond the enemy's remaining HP does not count.
  - Damage share is what limits a new track against a strong enemy (low mastery and the wrong
    attributes mean a small share), and it rewards a strong build in proportion. A generous hard
    ceiling per use (≈ 20% of the next requirement) only guards against bugs and exploits.

## Mastery trees

Each mastery has a **small tree**: roughly 6–10 nodes, two branches, and a node that needs both.

- Wand: a single-target branch (Mana Bolt → Piercing Bolt) and an area branch (Mana Burst →
  Scatter). The node needing both is a powerful small-area form.
- Fire: an infusion that applies to whatever weapon is held, then branches toward reach (flames
  extend slashes; bolts become fireballs) and toward spread (lingering burn, splash).

Branches grow from the chosen focus and from what skills do (decided 2026-10-26; see "Mastery XP
from use").

### Node kinds

Every node is one of three kinds, so it is always clear what selecting it does:

| Kind | Lives in | Selection |
|---|---|---|
| **Shape** | attack-type trees | One per weapon context. How the basic attack is delivered: Mana Ball, Piercing Bolt, Scatter, Slash. |
| **Infusion** | element trees | One or none. What the basic attack carries. Applies to any weapon held. |
| **Passive** | any tree | Always on once unlocked, everywhere. Nothing to select. |
| **Selectable passive** *(working name)* | any tree | Choose up to N. Stronger, playstyle-specific stat improvements; may be limited to weapon contexts. |

**Weapon contexts.** A shape node declares the contexts it physically fits (unarmed, one-handed
blade, dual daggers, two-handed, wand, ...). In a context, any unlocked shape from an attuned track
that fits it can be selected, and the choice is remembered per context. Bare-handed with a Magic
shape selected, the basic attack is that magical attack; with no fitting shape, bare hands punch
(Blunt). A dual-dagger form cannot be picked while holding a greatsword, but the rest of its branch
still can.

**Root forms and fallback.** Every track starts from one root node: its basic form, animated per
weapon but the same form. When the selected form does not fit what is held, or its requirements stop
being met, the weapon's default (the root of its track) is used as a fallback, and the selection is
kept for when it fits again. Selectable passives that do not fit go dormant the same way. The N
selectable passives are **one shared pool** for the character, so choices from both attuned tracks
compete.

**Attribute requirements.** Form nodes can require attributes as well as mastery, so the attribute
budget gates what a character can do: a strength-focused starter cannot shoot mana balls.
Attributes from gear count toward requirements (an attribute's source is metadata, not gameplay),
so an Intelligence ring can open Mana Ball and removing it triggers the fallback. When a weapon's
default form is itself gated (a wand's Mana Ball needs Intelligence), the character swings the
weapon physically, reusing an existing swing animation — chosen form → weapon default → physical
swing. At a shrine, attributes can be partially rewound or fully reset, both at a large cost.

## Forms — the basic attack

The basic attack (M1) is "use your weapon". Its **form** is how: composed in the trees, never picked
from a flat list.

**Form = selected shape (for the held weapon's class) + selected infusion.** Piercing Bolt + Fire II
is a Fire Bolt.

- **Generic rule.** Any shape works with any infusion: part of the damage converts to the element and
  the effects take its colour. No combination is ever a dead end, so experimenting is never wasted.
- **Named combinations.** A curated table gives specific pairings their own identity — name, visuals,
  mechanics:
  - Piercing Bolt + Fire II → **Fire Bolt** (own projectile)
  - Mana Ball + Fire III → **Fireball** (explodes)
  - Wide Slash + Fire III → **Fire Crescent** (a crescent leaves the swing; reach grows with Fire
    mastery)

  Adding an element or a shape never requires authoring every pairing; only the ones worth
  hand-crafting are.
- **Discrete and continuous growth.** Reaching a new node is a discrete step. Within a node, values
  scale with mastery level ("the crescent reaches further as mastery grows"), so a form keeps
  improving after it is unlocked.
- **Nodes describe themselves against the current selection.** The Fire II node reads "With Piercing
  Bolt: becomes Fire Bolt"; with Scatter selected it reads "fire scatter". This advertises named
  combinations before they are reached.
- **Only mastery and unique weapons change forms.** A unique weapon can grant a shape (available
  while equipped) or unlock a node.
- **Forms cost resources**, and the cost grows with the form's complexity. A fire slash may cost
  stamina and a little mana. Because higher forms cost more, earlier ones stay a real choice — cheap
  filler when resources run low — rather than being strictly replaced.

### Edge cases

- No element attuned: the shape alone, uninfused.
- Two attack-type masteries attuned: shapes from either that fit the held weapon's context are
  selectable; no infusion.
- Unattuning an element at the NPC: the infusion stays selected but loses the attunement bonus; the
  shape and all progress remain.
- Changing weapons: the shape is remembered per weapon context; the infusion carries over, so
  picking up a sword with Fire attuned gives a fire slash immediately.

## Player-facing UI

### Mastery pages

- **One mastery at a time.** The page shows a single tree — the Wand tree, say — not the attuned pair
  side by side.
- **An open canvas, not a scrolling panel.** The tree grows horizontally, nodes joined by lines, on an
  airy space the player pans around (an Excalidraw-like void), bounded so it cannot be panned far
  off.
- **Fog ahead.** Only one or two nodes past the player's frontier are visible; the rest of the tree
  is discovered by progressing.
- Shape and infusion nodes are selected here. The page states the result briefly; the full details
  live in the management space.

### Where everything lives

Menus are organised by the question the player is asking:

| Question | Where |
|---|---|
| Who am I? | **System** (exists): level, attributes, class, mastery levels, attunement |
| What do I carry and wear? | **Inventory**, **Equipment** (exist) |
| How do I fight? | **Loadout**: a fourth staged menu view, separate from Equipment |
| How do I grow? | **Mastery canvas**: a full-screen overlay, reached through links, not a tab |

Equipment's weapon slot shows the current form's name and links to Loadout.

### Loadout

A staged world panel like the other views, with a wider camera seat than Inventory's.

- **Weapon slot first, with the full form card**: the form's name; its recipe as links into the
  mastery canvas (*Shape: Piercing Bolt · Infusion: Fire II*); cost per step; damage split; what it
  scales with; its combo shape ("3 steps, knockback on the 3rd").
- **Slot sets** as tabs, each drawn exactly like the HUD skill bar so the two read as the same thing.
- **Skill library**: every granted skill, filterable by tag. Skills unusable with the held weapon are
  greyed out with the reason (the server already reports `wrong_weapon_class`). Assign by selecting a
  slot, then a skill, so it works on gamepad and touch; dragging can come later.
- **Attunement, read-only**: a header line, *"Attuned: Wand · Fire — change at an Attunement
  Shrine."*
- Detail for the selected skill or form opens in a **side slot**, the mechanism ItemInspect uses.

### Mastery canvas

A full-screen overlay to start with — the System's inner view — rather than a 3D constellation
around the character, which would bring back walls, depth sorting and foreshortening.

- The world dims and blurs behind it; the canvas pans by drag or right stick, within bounds.
- **A short entry sequence** carries the player from the world into the canvas, so it reads as going
  somewhere deeper rather than opening a page.
- Entry points: the recipe links on the Loadout form card, the mastery list in System, and System
  notifications (*"Fire Mastery 10 — a new path opens"*), which open the canvas centred on that node.
- One mastery at a time, with a selector to move between them; unattuned masteries are viewable but
  read as dormant.

### Later: live preview

Selecting a skill or form plays it on the player's own character, which the menu camera already
frames: animation and effects only, no request, nothing hit. **Only in safe zones**, where the player
does not need to watch their surroundings. Worth building, after the core screens exist.

## How it maps to code

The basic attack already resolves from a shared, deterministic input on both peers
(`BasicAttackProfileRegistry.resolve` over the combat loadout snapshot). Forms extend that input
rather than replace the mechanism:

> weapon class + selected shape + selected infusion + mastery levels → validate (shape fits the weapon,
> requirements met; else the class default) → apply infusion and mastery-scaled values → named
> combination override if one exists → resolved form (today's profile shape plus cost and on-hit
> effects)

- **Unlocks are derived, not stored.** Save branch XP, attunement, and the selections; compute
  what is available from them. Rebalancing an unlock level then needs no save migration, and the two
  peers cannot disagree about what is unlocked.
- **Cost moves onto the form.** Today it is static on the `BasicAttack` skill data
  (`costs = { 10, 12, 15 }`, Stamina).
- **Forms may override the projectile.** Today the weapon alone names it
  (`WeaponConfig.projectile`); Fire Bolt and Fireball need their own. The weapon still owns damage,
  damage types and attack speed.
- **Knockback, recovery and on-hit effects** are already per-step profile data
  (`docs/tasks/combat-feel-and-entity-sync.md`); infusions and named combinations layer onto them.

## Build order

1. **Server-owned, persisted player state.** *Done (2026-10-25).* The save layer
   (`server/PlayerData/`, ProfileStore) with a versioned schema that reserves `progression`
   (masteries, attunement, shape and infusion selections); server-owned skill slot sets
   (`server/Loadout/LoadoutService`, mirrored by `client/SkillsFramework/SkillSlots`); inventory,
   equipment, items and attribute allocation saved, and kept through death (a player keeps one
   entity id per session).
2. **Form registry.** *Done (2026-10-25).* Basic attack profiles are shapes: `displayName`, `cost`
   (the single source for the server's charge and the client's prediction), `requires` (mastery
   levels), `parent` (lineage) and `shapeFor` (classes it can be selected for besides the one it is
   the default of). `server/Forms/FormService` validates selections (`LoadoutSelectShape`), keeps
   them per class key in the save, and writes the selected, unlocked shape into the combat loadout
   snapshot (`basicAttackShape`), which both peers resolve from. Proven with `unarmed_rapid_jabs`
   (needs Unarmed 1; `ServerStorage.DevSetMastery` stands in for mastery until step 3). No UI yet.
3. **Mastery service and the mastery page.** *Done (2026-10-26, verified in play;
   `docs/tasks/mastery-model-v2.md`):* the six launch tracks; trees as data
   (`shared/progression/MasteryTrees`, from `progression-launch-content.md`); XP saved per branch
   (save schema v2, migrating the first cut's per-weapon tracks); use XP below the training cap,
   damage-share XP from NPC hits with a per-use ceiling, element XP from `byType`; form unlocks from
   the tree; the canvas drawing the new trees with branch progress. Not yet: attunement, attribute
   requirements (shown, not enforced), passive effects, and real enemy values (NPC specs carry a
   placeholder `progression.masteryValue`).
   *Also done (2026-10-26, `docs/tasks/character-level-and-npc-death.md`):* the character level
   stream's first source -- NPCs can now die (and respawn), kill XP is shared by the health each
   player removed, levels grant attribute points, and STATUS shows the real level.
   *Also done (2026-10-27, `docs/tasks/attunement-and-gear-locks.md`):* attunement (slots at
   levels 3 and 6, placeholder), changed at an Attunement Shrine (free until currency exists), with
   unattuned attack-type forms dormant; gear requirements enforced as hard locks.
4. **Infusions and named combinations,** including new on-hit mechanics (e.g. the crescent).
5. **Unique-weapon forms.**

## Open questions

- The launch trees, classes and milestones have a first draft in `progression-launch-content.md`,
  expected to change as content gets more thought.
- The mastery canvas entry sequence: what it looks like, and how long it may take before it feels
  slow on the tenth visit.
