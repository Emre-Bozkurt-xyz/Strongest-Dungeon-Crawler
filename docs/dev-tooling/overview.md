# Dev tooling

Commands, stages, characters and scenarios for testing in Studio. Everything here runs only when
`DevAccess.isEnabled()` (Studio only; live servers never have dev tooling); it is started from the
Studio-gated `DevHooks` bootstrap entries (`src/server/dev/InitDev.luau`,
`src/client/dev/InitDev.luau`). `DevAccess.canUse` authorizes every server request.

| Piece | Path |
| --- | --- |
| Command parsing and registry (shared) | `src/shared/Dev/` (`CommandLine`, `CommandRegistry`, `CommandHelp`, `DevAccess`) |
| Server commands | `src/server/dev/Commands/` (`init.luau` = `DevCommands`, `Defs/*.luau`) |
| Client commands | `src/client/dev/Commands/` (`init.luau` = `DevCommandsClient`, `Defs/*.luau`) |
| Stages | `src/server/dev/Stages/` |
| NPC adapter | `src/server/dev/Spawning.luau` |
| Characters | `src/server/dev/Characters/` (presets in `Presets/`, fields in `Types.luau`) |
| Scenarios | `src/server/dev/Scenarios/` (definitions in `Defs/`) |
| Dev session kit | `src/server/dev/StarterKit.luau` |
| In-game console | `src/client/ui/dev/Console/` |

## The console

Backquote (`` ` ``) toggles it, in any dev session (mounted by `ScreenRegistry` when
`DevAccess.isEnabled()`). It docks to the right edge at full height; while open it frees the cursor
and blocks gameplay input (`InteractionStateController.setInputCaptured`), leaving the HUD up. Clicks
on the console are taken by its own controls and never reach gameplay bindings; a click on the world
beside it reaches them but is refused while the capture holds; keys typed into any console field go
to the field. Open state, tab, typed text and history survive respawns.

Laid out as a command palette, top to bottom:

- **Command line** (the main way in; it takes the keyboard when the console opens, and any click in
  the console hands it back): autocomplete from the descriptors drops under it (names, then each
  argument's choices; Tab takes the first). Below it, one line: the usage of the command being typed
  with the current argument underlined, else the last result in green or red (cut to two lines; the
  Log has it whole).
- **Rail** of the seven tabs on the left, drawn as line icons with the name in a tooltip on hover.
- **Content column:** dim section labels over one-line rows (state dot, title, chips at the right).
  Rows are selectable by click or by Up/Down while the command line is empty; the selected row's
  details and actions sit in a **detail pane** pinned to the foot of the column, primary action
  first. Long lists scroll; the pane and the chrome stay put.
- **Status strip** along the bottom: the save in use on the left (a red strip with a warning glyph,
  "Real save · changes are permanent", when no preset is applied; a neutral strip with a green dot
  and the preset name when sandboxed, plus "edited" once the character editor has changed it) and
  "scenario · stage" on the right.

Keys on the command line: Enter runs the line; on an empty line it runs the selected row's primary
action, whose command shows meanwhile as ghost text in the input (with the action's name and the
return key at the right), so the UI teaches the commands it runs. Tab on an empty line puts the ghost
command on the line to edit. Up/Down walk the history once the line has text (or once walking it);
Ctrl+Up/Down walk it from anywhere.

| Tab | Rows | Detail pane / other |
| --- | --- | --- |
| Scenarios | scenarios, grouped by id prefix; dot = loaded | stage, character, source, what Play loads; Load / Reload (primary), Pin for play, Exit scenario; "On play" chips (last loaded, always default) |
| Character | the character editor (see below); Presets swaps in the preset list: dot = applied, chip = saved / this session | preset list: Apply (primary), View source, Delete (saved presets) |
| World | stages, then NPCs (thin health bar) | marker chips teleport (`tp`), show-markers switch, one-line spawn form, Despawn all; stage: Load map (primary), Unload; NPC: Hit (primary, amount set in the pane), Apply status, Inspect, Despawn (that kind) |
| Debug | server and client flags in two columns of switches; Enter flips the selected one | tuning overrides (Edit, Reset, Reset all), set-a-value line with path suggestions |
| Commands | every command, mono name + summary, grouped as the registry groups them; filter pinned above | the form built from the descriptor, the exact command line above Run (primary), Clear, result and data |
| Log | Commands / Output switch; time, mono command, coloured result; a picked command runs again on Enter | Failed / Errors chip filters, Clear |
| Inspect | target chips (you, each NPC) pinned above; Up/Down walks them | stats as base → final with modifiers indented under each, a filter and Modified chip; statuses and the skill session in the pane; Enter logs `inspect` |

While closed, client warnings and errors are counted in a badge at the right edge.

### The Character tab

An editor over the whole live character; every change applies to you at once. Code:
`Console/Tabs/CharacterTab/` (`init.luau` the tab, `EditorStore.luau` its data and edits,
`Sections/` one file per section, `ItemEditor.luau`, `PresetList.luau`, `Parts.luau`).

- **Header (pinned):** "Editing [base ▾]" — the preset the build came from, "real save", or "real save
  copy"; picking another applies it (`character apply` / `character restore`). An amber "n edits" chip
  while the build differs from its base, and Presets / Editor to swap the accordion for the preset
  list. Under it one line says where edits go: on the real save, that the first edit moves you onto a
  sandbox copy.
- **Accordion (scrolls):** nine sections, each with a one-line summary at the right while closed;
  which are open is remembered.
  - *Level*: level stepper (sets total XP to that level's threshold), exact total XP, XP to next.
  - *Attributes*: a stepper per attribute and for unspent points; the number can be typed.
  - *Pools*: per pool a slider, an exact field (`81` or `60%`), the live current / max, a hold
    switch; Fill all, Empty all.
  - *Mastery*: a node search (name, kind, what unlocks it; picking one runs `character unlock`), the
    attunement slots, an XP / Rank toggle, then every track: attune star, level, and trunk / a / b
    typed in place (`max` or the raise-to-max button caps a branch).
  - *Skills and bar*: owned skills as chips (click to remove) and an add-skill search; each bar set as
    a row of slot pickers limited to owned skills; click a set's chip to make it active.
  - *Equipment*: a row per filled slot (item, rarity, affixes) with edit and clear; edit opens the item
    editor under the row (item limited to what the slot takes, rarity, item level, affixes with tier,
    add / remove). Empty slots are counted, with an "equip an item" search.
  - *Bag*: rows with a count stepper (stackable items), edit (the same item editor), remove; an add
    search.
  - *Form and passives*: shape per weapon class, infusion, passives within the level's slots; locked
    choices stay listed, disabled, with what opens them.
  - *Base stat overrides*: each override with its value and remove; an add-stat search.
- **Save pane (pinned):** what was edited, a name (a new one by default), Save preset (primary),
  Revert, Copy source (the live build's Luau, selectable), Restore real save.

Edits are sent as one `character set` patch per settled change (stepper clicks and typing are
coalesced; sliders send on release); the control shows the new value at once and snaps back, with the
server's reason beside it in red, when the patch is refused. Pools follow the replicated stats a few
times a second; the rest of the state is read again every few seconds while the tab shows, when
progression or the preset changes, and comes back with every edit. Tab and Shift+Tab walk the fields,
Enter commits one; typing in a field never reaches gameplay or the command line.

Every action is a command through `DevCommandsClient.run`; lists are read with `query`. The look is
the console's own: palette, faces (Builder Sans, Builder Mono), type sizes, spacing and radii live in
`Console/Theme.luau`, and screens are composed from the primitives in `Console/Controls.luau` (Text,
Stack, Line, SectionLabel, Row, Chip, Kbd, Button, IconButton, Input, Field, Stepper, Slider, Select,
Search, Switch, Bar, Section, KeyValues, FormRow, DetailPane, TabLayout, Empty, Result, CodeView,
RailItem). Select and Search float their lists in an overlay layer over the whole dock, so a scrolling
list never clips them. Icons are Path2D line art in
`Console/Glyphs.luau`. A tab publishes its rows, selection and primary action with
`Selection.usePublish` (`Console/Selection.luau`), which is what Up/Down, Enter and the ghost command
act on.

## Running commands

A command line is a name (one or two words) followed by arguments; quotes group words, JSON
arguments are written inline. Every entry point returns a `Result`: `{ ok, message, data? }`.

- **Server command bar / MCP (Server datamodel):**
  `game.ServerStorage.Dev:Invoke("scenario load combat/status-marks")`. The second argument is the
  player to act as; nil means the first player in the server.
- **Client command bar / MCP (Client datamodel):**
  `game.ReplicatedStorage.DevClient:Invoke("tune get Camera.baseline.shoulderBack")`. Runs client
  commands locally and forwards everything else to the server as this player, exactly as the console
  will. `DevClient` exists only on that client.
- **Console (client UI):** `DevCommandsClient.run(text)`, `DevCommandsClient.query(text)` (the same,
  without adding to the log; for UIs reading lists), `DevCommandsClient.describe()` (every command in
  both realms as data, with `realm`), `DevCommandsClient.onLog(callback)`. The server end is
  `ReplicatedStorage.DevRemote` (`InvokeServer("run", text)`, `InvokeServer("describe")`), which
  authorizes each request with `DevAccess.canUse`.

Command code and the scripts you run share no module cache, so always go through these instances.

### Commands

Usage strings are what `help` prints; `<x>` is required, `[x]` optional, `[x=1]` has a default.

| Command | Data |
| --- | --- |
| **Character** | |
| `character apply <preset>` | `{ name }` |
| `character restore` | — |
| `character list` | `{ presets = { { name, source = "file"\|"saved"\|"session", current } }, current, store = { persists, reason? } }` (`current` is `""` on the real save) |
| `character current` | `{ name, sandboxed }` |
| `character save <name>` | `{ name, path, source, storage = "saved"\|"session" }` — `source` is the Luau of your live build |
| `character delete <preset>` | `{ name }` — saved presets only |
| `character show [preset]` | `{ name, spec, source }` — no preset: your live build |
| `character schema` | the editor's `Schema` (below) |
| `character state` | the editor's `State` (below) |
| `character set <json>` | `{ state, problems?, inPlace? }` — a refused patch has `ok = false` and `problems` |
| `character revert` | — |
| `character unlock <node>` (id or display name) | `{ state, problems? }` |
| `character pool <pool> <value>` (`81`, `60%`, `full`, `empty`) | `{ state, problems? }` |
| `character hold <pool> [on=true]` | `{ state }` |
| **Scenario** | |
| `scenario load <id>` | the loaded `ScenarioInfo` |
| `scenario reload` | the loaded `ScenarioInfo` |
| `scenario exit` | — |
| `scenario list` | `{ scenarios = { ScenarioInfo } }` |
| `scenario current` | `ScenarioInfo`, or `{}` when none is loaded |
| `scenario boot [last\|default\|id]` | `{ boot }`; no argument: `{ boot, target }` (the choice and the id Play would load) |
| **World** | |
| `stage load <name>` | `{ name, markers }` |
| `stage unload` | — |
| `stage list` | `{ stages = { { name, current } } }` |
| `markers [show\|hide]` | `{ visible }`; no argument: `{ visible, stage, stageMarkers, worldMarkers }` |
| `tp <marker>` | — |
| `tp start` | — |
| **NPC** | |
| `spawn <kind> [count=1] [options]` | `{ kind, count }` |
| `despawn <target>` (`all` or a kind) | `{ removed, cancelledRespawns }` |
| `npcs [kind]` | `{ npcs = { { name, kind, entityId, tag, dead, position = {x,y,z}, health, maxHealth } } }` |
| **Player** | |
| `pool <pool> <delta>` | — |
| `heal` | — |
| `give <itemId> [count=1] [normal\|magic\|rare\|unique]` | — |
| `drop [count=1]` | — |
| **Progression** | |
| `xp <amount>` | — |
| `mastery <track> <trunk\|a\|b> <xp>` | — |
| **Combat** | |
| `hit <npc> <amount>` (`npc`: a name, or an entity id from `npcs`) | — |
| `status <npc> <effect> [params]` | — |
| **Debug** | |
| `inspect [target=me]` (`me`, an NPC name or an entity id) | `{ name, entityId, isPlayer, stats = { { name, base, final, current?, max?, modifiers = { { source, name, type, value } } } }, statuses = { { id, stacks, remaining } }, session? }` |
| `flag <name> <value>` / `flags` | `flags`: `{ [name] = boolean }` |
| `cflag <name> <value>` / `cflags` (client) | `cflags`: `{ [name] = boolean }` |
| `cooldowns` (client) | `{ cooldowns = { { key, remaining } } }` |
| `help [command...]` (client: both realms) | `{ commands = { Descriptor } }` when listing |
| **Tuning** | |
| `tune [command...=help]` (client) | `{ lines }` |

`ScenarioInfo` is `{ id, title, description, stage?, character, source = "code"|"stage", current }`;
`character` is a preset name, `"custom"` (inline spec) or `"keep"`.

`spawn` options are spawn options as a JSON object, e.g. `spawn Slime 3 {"respawnDelay": 5}`.
`character show` turns item specs such as `{ "iron_sword", rarity = "magic" }` into JSON objects
with string keys (`{ "1": "iron_sword", "rarity": "magic" }`); `source` is the exact Luau.

Commands that change progression or the bag (`give`, `drop`, `xp`, `mastery`) act on whichever save
is in use. On a character preset that is the stand-in; on your real save they change your real save.
The `character` editing commands (`set`, `unlock`, `pool`) never do: on the real save they first move
you onto a sandbox copy of it.

### Adding a command

Add a def to any module under a `Defs` folder (server or client); each module returns a list:

```lua
{
	name = "stage load",            -- one or two words
	group = "World",
	summary = "...",
	args = { { name = "name", type = "choice", choices = function() return Stages.list() end } },
	run = function(context, args) ... end,   -- context.player, context.realm
}
```

Argument types: `string`, `number`, `integer` (`min`/`max`), `boolean`, `choice` (`choices`, a list
or a function), `json`, `rest` (the remainder of the line; last). `default` makes an argument
optional. Return nil, a message string, or `{ message, data, ok }`; raise
`CommandRegistry.fail(message)` (server: `Support.fail`) for a failure the user caused. `data` must
survive JSON. Keep handlers thin: logic belongs in the module the command drives.

## Stages (authoring in Studio)

A stage is a Model under `ServerStorage.Scenarios`. One is loaded at a time, cloned into
`Workspace.Stage` with its pivot at `(0, 0, 10000)` (attribute `KeepPosition = true` keeps it where
it was built). Set the Model's pivot (or its PrimaryPart's `PivotOffset`) at floor level.

**Markers** are BaseParts or Attachments that are tagged `ScenarioMarker` or sit anywhere inside a
Folder named `Markers`. The Name is the marker name; names may repeat. When a stage loads, marker
parts become invisible, anchored and non-colliding (`markers show` brings them back with labels).
Repeated names are ordered by an `Order` attribute, else by distance from the stage pivot.

| Convention | Meaning |
| --- | --- |
| marker named `PlayerStart` | where players are placed (heading kept, raised to standing height) |
| marker attribute `Spawn = "<kind>"` | the scenario spawns that NPC kind there |
| marker attribute `Count` | how many to spawn, in a row across the marker |
| other marker attributes | spawn options, name lower-cased: `RespawnDelay` -> `respawnDelay`, `AreaLevel`, `Rank`, `XP`, `MasteryValue` |
| Model attribute `Title`, `Description` | how the stage is listed as a scenario |
| Model attribute `Character` | a preset applied when the stage is loaded as a scenario |
| Model attribute `AreaLevel` | inherited by NPCs spawned inside it |

Spawn markers can sit anywhere above the floor: NPCs are dropped onto the first surface below.
Tagged markers placed straight in the baseplate world are world markers (`tp`, `s.marker` fall back
to them; a world `PlayerStart` replaces the SpawnLocation as the world start). Only dev code hides
and disarms markers, so world markers placed in a map that ships must be authored invisible and
non-colliding.

A stage that no scenario definition names is a scenario by itself (`scenario load <StageName>`):
its spawn markers are spawned, its `Character` applied, players placed at `PlayerStart`. That is the
way to author a scenario entirely in Studio. `ExampleArena` shows every convention: a `PlayerStart`,
three `TrainingDummy` markers (`Spawn = "Dummy"`, `Order` 1-3), a `SlimeSpot` (`Spawn = "Slime"`,
`RespawnDelay = 8`), `Center` and four `Pillar` markers. It is named by `arena/pillar-drill`, so it
does not also appear as its own scenario.

`stage load` loads only the map (no spawns, no character); use `scenario load` for the full set-up.

## Characters

A character spec declares a whole build; every field is optional and an empty spec is a brand-new
save. Full field reference: `src/server/dev/Characters/Types.luau`.

```lua
-- src/server/dev/Characters/Presets/frost-caster.luau
return {
	extends = "starter",                       -- start from another preset
	level = 10,                                -- or xp = 1234
	attributes = { Intelligence = 12, unspent = 2 },
	mastery = { Magic = { trunk = "mastered", a = { rank = 2 } }, Frost = { trunk = 150 } },
	attuned = { "Magic", "Frost" },
	bar = { { "BasicAttack", "CascadingManaBalls", "Dash", "DodgeRoll" } },
	equipment = { Main = { "crooked_wand", rarity = "rare", affixes = { "scholar" } } },
	bag = { { "mana_potion", 5 } },
	pools = { Mana = 0.5 },                    -- fraction (<= 1) or absolute
	stats = { AttackSpeed = 1.2 },             -- session-only base overrides
}
```

Applying a character sets your real save aside (`PlayerDataService` sandbox: nothing is written to
the profile until you restore or leave) and rebuilds you from the spec. `character restore` or
`scenario exit` returns to the real save as it was. The player attribute `DevCharacter` holds the
applied preset name (`""` on the real save; `"custom"` for an inline spec; `"real save copy"` for a
sandbox copy of the real save made by the editor), and `DevCharacterEdited` whether the editor has
changed it since.

Items dropped in the world stay with the kind of save they came from, scenario or not
(`Characters/Drops.luau`). A drop belongs to the save its owner (who dropped it, or who loot was
dropped for) was on when it appeared; a drop with no owner belongs to the real world. You can only
pick up drops of the kind of save you are on now. A preset's drops are removed when you leave that
preset (`character restore`, applying another preset, leaving the game); real-save drops stay in the
world and cannot be picked up until you are back on the real save.

**Saved presets:** build a character in play (or in the editor), then `character save <name>`. The
spec is kept in the `DevCharacterPresets` DataStore (one key, `presets`, shared by everyone working
on the place; never the player save; `Characters/Saved.luau`), read once when dev tooling starts, so
it is there the next time you press Play. Saved presets are listed with the file presets (`source =
"saved"`) and work everywhere a preset name does: `character apply`, `extends`, a scenario's
`character`, `character show`. A name a file preset owns is refused; `character delete <name>`
removes a saved one. Without DataStore access (or when a read or write fails) presets are kept for
the session only (`source = "session"`) and the save's message says so. The Luau source is printed
and returned in `data.source`: paste it into `src/server/dev/Characters/Presets/<name>.luau` to commit
it as a file. Saving while on a preset makes the saved preset the base you are editing against.

### Editing the live character

`character set <json>` lays a partial spec over your live build and applies it at once
(`Characters.edit`, `Characters/Editor.luau`). Merge rules are the spec's (maps merge, lists and items
replace, `false` removes), with two additions: `level` and `xp` replace each other, and a bag entry
`{ "keep": i, "count": n? }` stands for the i-th row of the state's `bag` (so unchanged items keep
their exact rolls). Item specs in JSON write positional entries as `"1"`, `"2"`.

- The merged build is checked with the preset validator first; if anything is wrong nothing is applied
  and `data.problems` lists `{ field, message }` (`field` is the spec path: `level`, `attuned`,
  `mastery.Fire.trunk`, `passives[1]`, `equipment.Main`, ...).
- On the real save, the first edit captures the build as it is and moves you onto a sandbox copy of it
  before anything changes (`DevCharacter` = `"real save copy"`); the real profile is never written.
- `level`/`xp`, `attributes`, `mastery`, `attuned` and `pools` are set on the live player in place
  (`CharacterService.setXp`, `AttributesManager`, `MasteryService.setBranchXp`,
  `AttunementService.assign`, pool writes). Anything else (`skills`, `bar`, `activeSet`, `equipment`,
  `bag`, `capacity`, `shapes`, `infusion`, `passives`, `stats`) rebuilds you from the merged spec, which
  also clears cooldowns, statuses and the skill in progress, and rerolls the values of any item given
  without its exact meta.
- Each player on a preset has a base (the preset, or the real save for a copy) and the build right after
  it was applied; `state.edited` lists the paths (`level`, `attributes.Strength`, `mastery.Fire`,
  `bag`...) an edit made differ from it. Changes the game makes on its own (XP from kills, pools in a
  fight) are not counted. The player attribute `DevCharacterEdited` is true while any are.
- `character revert` re-applies the base preset as it is defined now; on a copy of the real save it
  goes back to the real save.
- `character unlock <node>` raises every branch below what opens the node (never lowers one) and says
  what else it needs: its track attuned (end nodes, and attack-type nodes past the root), a passive
  slot (selectable passives), or that no shape implements it yet.

**Hold** (`character hold <pool>`, `Characters/Holds.luau`): pins a pool at its value until released.
A hit, a skill's cost or a rebuild's refill is undone in the same call that made it (through
`StatsManager.onPoolChanged`); regeneration, which writes pools without reporting it, is undone the
next frame. A lethal hit on held Health still lands (damage number, hit reaction, credit to the
attacker) but Health is back at the held value before the hit returns, so it never rests at zero.
Setting a held pool (`character pool`, the slider) moves the hold with it. Holds are session tooling,
not part of any spec; `character restore` (and leaving) releases them. A hold does not move you off
the real save.

`Schema` (`character schema`, built once per server, `Characters/Schema.luau`):

```
{ attributes = { names, min, max, defaultUnspent }, pools = { "Health", ... },
  level = { max, totals = { [level] = total XP }, pointsPerLevel },
  mastery = { trunkCap, branchCap, trunkRanks, branchRanks, branchEntry, joinRank, maxLevel,
              levelTotals, tracks = { { id, name, family, branches = { a, b } } },
              nodes = { { id, name, kind, track, branch, rank, requirement = { trunk?, a?, b? },
                          unlockXp, unlockRank, needsAttunement, needsPassiveSlot, built } } },
  attunementSlotLevels, passiveSlotLevels, skills = { { id, name } }, bar = { sets, slots },
  equipSlots, rarities, items = { { id, name, equipment, slots, weaponClass?, twoHanded?, stackLimit,
                                    rarities, baseItemLevel?, affixes = { { id, kind, tiers, minLevels } } } },
  classKeys, shapes = { [classKey] = { { id, name } } }, infusions = { { id, name, track } },
  passives = { { id, name, track } }, stats = { { name, default } }, capacity = { default, max } }
```

`State` (`character state`, and the `state` of every editing command):

```
{ sandboxed, base ("" on the real save or a copy of it), name (what DevCharacter shows),
  baseSource = "real" | "real copy" | "file" | "saved" | "session" | "custom" | "missing",
  edited = { path }, editedSummary, spec (the live build, JSON-safe),
  level, xp, xpInto, xpToNext?, levelFloor, attributes = { [name] = base }, unspent,
  masteries = { [track] = { level, trunk, a, b, ranks = { trunk, a, b }, attuned } },
  attunement = { tracks, used, slots, nextSlotLevel? },
  pools = { [pool] = { current, max, held? } }, skills, bar = { { slot } }, activeSet, slotsPerSet,
  equipment = { [slot] = ItemRow }, bag = { ItemRow & { slot } }, capacity,
  forms = { classes = { [classKey] = { selected?, default, options = { { id, name, locked? } } } },
            infusion = { selected, options = { { id, name, locked? } } },
            passives = { selected, used, slots, nextSlotLevel?, options = { { id, name, track, locked? } } } },
  stats = { [stat] = base } }
ItemRow = { itemId, name, count, rarity?, itemLevel?, affixes = { { id, tier, label } }, stackLimit }
```

`locked` is why an option cannot be chosen ("needs Blunt trunk → 120 and Blunt attuned").

The `starter` preset and the dev session's per-player kit (owned skills, starting items, Perception
point, AttackSpeed base) both read `StarterKit.luau`; change the kit there.

## Scenarios

A scenario is a stage + a character + an optional setup script, each optional. One is loaded at a
time for the whole server; the character goes on the invoking player, and every player is placed at
the start. Switching tears the previous one down completely: its NPCs (by spawn tag, dying ones and
pending respawns included), timers, tracked instances, loot dropped in the world while it ran, and
the debug flags and tuning it changed.

Loot is judged by whose save it came from (see Characters). A drop made on a character preset is
removed. A drop made on the real save is a real item: teardown puts it back in its owner's bag, or
leaves it in the world when it cannot (bag full, owner now on a preset) and returns it at a later
teardown once the owner is back on the real save.

Definitions are ModuleScripts under `src/server/dev/Scenarios/Defs/`; the id is the path below it
(`combat/status-marks`). A module returns a table, or `Scenarios.define({ ... })` to have it checked
when it loads.

```lua
-- src/server/dev/Scenarios/Defs/arena/burning-row.luau  (id "arena/burning-row")
return {
	title = "Burning row",
	description = "...",
	stage = "ExampleArena",        -- omit for the baseplate world
	character = "mid-blade",       -- preset name, inline spec, or "keep" (default)
	flags = { hitboxes = true },   -- server DebugConfig flags for the duration
	clientFlags = { inputFlow = false },
	tune = { ["Camera.baseline.shoulderBack"] = 8 },   -- client tuning for the duration
	setup = function(s)
		local dummies = s.spawnRow("Dummy", 3, "Center", { spacing = 8 })
		s.status(dummies, "Burn", { damagePerTick = 1 })
	end,
}
```

Load order: tear down the current scenario, load the stage (or unload it), spawn the stage's spawn
markers, apply the character, place players, apply flags and tuning, run `setup`. A failing step is
reported by name (`scenario 'x' failed at setup: ...`), everything built so far is removed and the
default scenario is loaded instead.

### The setup scope `s`

| Member | |
| --- | --- |
| `s.id`, `s.player`, `s.players`, `s.stage` (nil without a stage), `s.folder` | context; put your instances in `s.folder` |
| `s.marker(name) -> CFrame` | stage marker, else world marker; a missing one is an error listing what exists |
| `s.markers(name) -> { CFrame }` | every marker with that name, in order |
| `s.spawn(kind, where, options?) -> Model` | `where` is a marker name, CFrame or Vector3; dropped onto the ground |
| `s.spawnRow(kind, count, where, { spacing?, options? }) -> { Model }` | a row across `where` |
| `s.spawned(kind?) -> { Model }` | living NPCs of this scenario, spawn markers' included |
| `s.status(target, effectId, params?) -> number` | target: a Model, a list, or a kind name; from `s.player` |
| `s.give(itemId, count?, meta?)` | into `s.player`'s bag |
| `s.run(commandText) -> Result` | any registry command as `s.player`; failure raises |
| `s.after(seconds, fn)`, `s.every(seconds, fn)` | cancelled on teardown |
| `s.track(instance) -> instance`, `s.onCleanup(fn)` | destroyed / called on teardown |

### Shipped scenarios

- `default` — the baseplate sandbox: a training dummy, a slime that respawns, a placeholder
  attunement shrine (at world markers `DummySpot`, `SlimeSpot`, `Shrine` when the baseplate has them).
- `combat/status-marks` — three dummies near the spawn kept under ailments.
- `arena/pillar-drill` — `ExampleArena` as `mid-blade` against respawning slimes, hitboxes drawn.

### Boot and replicated state

Pressing Play loads the scenario you last loaded successfully (kept per user in the `DevScenarios`
DataStore, never in the player save). `scenario boot default` always starts in the default scenario,
`scenario boot <id>` in that one, `scenario boot last` restores the default behaviour. Without
DataStore access, or if the boot scenario no longer exists, the default scenario loads. `scenario
exit` does not change what boots next.

`ReplicatedStorage.DevState` attributes, kept by the modules: `ScenarioId`, `ScenarioTitle`,
`StageName` (also follows `stage load`), `Revision` (bumped on every change), and `ClientOverrides`
(the JSON the client applies for `clientFlags` and `tune`; empty when none). Each Player has
`DevCharacter` and `DevCharacterEdited`.

## What dev tooling expects from the NPC rework

Dev tooling reaches NPCs only through `src/server/dev/Spawning.luau`; its header lists what it needs
from an NPC system (spawn by kind with options, tags that survive respawn, enumeration, clean
removal that cancels pending respawns, AI freeze, inspection). Options a system cannot honour are
ignored with one warning, so scenarios may already ask for features that do not exist yet. When the
NPC system is replaced, only `Spawning.luau` should need to change.
