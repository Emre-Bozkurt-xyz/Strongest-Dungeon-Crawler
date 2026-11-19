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
and blocks gameplay input (`InteractionStateController.setInputCaptured`), leaving the HUD up. Open
state, tab, typed text and history survive respawns.

- **Header:** scenario (title + id), stage, and the character: a green PRESET line when sandboxed, a
  red REAL SAVE band when `give`/`xp`/`mastery`/`drop` would change the real save.
- **Command line** (every tab): autocomplete from the descriptors (names, then each argument's
  choices), Tab takes the first suggestion, Up/Down history, Enter runs; the last result is shown in
  green or red.
- **Tabs:** Scenarios (grouped by id prefix; load, reload, load default, exit; what Play boots),
  Character (presets, restore, save-as with its Luau source, any preset's source, XP / mastery / give /
  pools / drop), World (stages, markers with teleports, spawn palette, despawn, live NPC list with hit,
  status and inspect per row), Debug (server and client flags, tuning overrides), Commands (every
  command with a form built from its descriptor, so new commands appear with no UI work), Log (what
  the console ran, and client warnings/errors), Inspect (`inspect` for you or an NPC, read live).
- While closed, client warnings and errors are counted in a badge at the right edge.

Every action is a command through `DevCommandsClient.run`; lists are read with `query`.

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
| `character list` | `{ presets = { { name, source = "file"\|"session", current } }, current }` (`current` is `""` on the real save) |
| `character current` | `{ name, sandboxed }` |
| `character save <name>` | `{ name, path, source }` — the Luau source of your live build |
| `character show [preset]` | `{ name, spec, source }` — no preset: your live build |
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
applied preset name (`""` on the real save; `"custom"` for an inline spec).

Items dropped in the world stay with the kind of save they came from, scenario or not
(`Characters/Drops.luau`). A drop belongs to the save its owner (who dropped it, or who loot was
dropped for) was on when it appeared; a drop with no owner belongs to the real world. You can only
pick up drops of the kind of save you are on now. A preset's drops are removed when you leave that
preset (`character restore`, applying another preset, leaving the game); real-save drops stay in the
world and cannot be picked up until you are back on the real save.

**Capture -> preset:** build a character in play, then `character save <name>`. The Luau source is
printed to the output and returned in `data.source`; the capture is also usable as a preset for the
rest of the session (`character apply <name>`, `character show <name>`). The game cannot write repo
files: paste the source into `src/server/dev/Characters/Presets/<name>.luau` to keep it.

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
`DevCharacter`.

## What dev tooling expects from the NPC rework

Dev tooling reaches NPCs only through `src/server/dev/Spawning.luau`; its header lists what it needs
from an NPC system (spawn by kind with options, tags that survive respawn, enumeration, clean
removal that cancels pending respawns, AI freeze, inspection). Options a system cannot honour are
ignored with one warning, so scenarios may already ask for features that do not exist yet. When the
NPC system is replaced, only `Spawning.luau` should need to change.
