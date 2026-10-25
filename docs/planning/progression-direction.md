# Progression Direction — masteries, attunement, classes, forms

Status: **direction agreed 2026-10-25, nothing built.** This fixes the shape of the system. Content
(the actual masteries, trees, classes, numbers) and the management space are still to be designed.

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

A mastery is a progression track with its own level, raised by use: swinging a sword raises Sword,
dealing fire damage raises Fire. Two families:

- **Weapon masteries** — Sword, Wand, Dagger, ... (one per weapon class).
- **Element masteries** — Fire, Frost, ... An element is not tied to a weapon: fire mastery shapes a
  mage's bolt and a warrior's slash alike.

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

### 5. Gear requirements — soft, not locks

Weapons ask for attributes. Below the requirement the weapon still works, with a penalty (less
damage, slower swings). Together with a low weapon mastery (base form only, no bonuses) this is what
makes off-spec play weak rather than forbidden.

## Mastery trees

Each mastery has a **small tree**: roughly 6–10 nodes, two branches, and a node that needs both.

- Wand: a single-target branch (Mana Bolt → Piercing Bolt) and an area branch (Mana Burst →
  Scatter). The node needing both is a powerful small-area form.
- Fire: an infusion that applies to whatever weapon is held, then branches toward reach (flames
  extend slashes; bolts become fireballs) and toward spread (lingering burn, splash).

Open: whether a branch grows from how the player fights (single-target hits feed the single-target
branch) or from a chosen training focus. The first fits "grow by doing"; the second is easier to
read.

### Node kinds

Every node is one of three kinds, so it is always clear what selecting it does:

| Kind | Lives in | Selection |
|---|---|---|
| **Shape** | weapon trees | One per weapon class. How the basic attack is delivered: Mana Ball, Piercing Bolt, Scatter, Slash. |
| **Infusion** | element trees | One or none. What the basic attack carries. Applies to any weapon held. |
| **Passive** | any tree | Always on once unlocked. Nothing to select. |

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
  - Slash + Fire III → **Fire Crescent** (a crescent leaves the swing; reach grows with Fire mastery)

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
- Two weapon masteries attuned: the held weapon's tree supplies the shape; no infusion.
- Unattuning an element at the NPC: the infusion drops; the shape and all progress remain.
- Changing weapons: the shape is remembered per weapon class; the infusion carries over, so picking
  up a sword with Fire attuned gives a fire slash immediately.

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

- **Unlocks are derived, not stored.** Save mastery levels, attunement, and the selections; compute
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
3. **Mastery service (minimal)** and the mastery page with fog and locked nodes.
4. **Infusions and named combinations,** including new on-hit mechanics (e.g. the crescent).
5. **Unique-weapon forms.**

## Open questions

- How XP splits between character level and masteries, and what feeds each mastery.
- Branch growth: by how the player fights, or by a chosen focus.
- Tree sizes; the launch set of masteries, classes and hybrids; milestone levels.
- Whether element masteries also improve skills, or only forms.
- The mastery canvas entry sequence: what it looks like, and how long it may take before it feels
  slow on the tenth visit.
