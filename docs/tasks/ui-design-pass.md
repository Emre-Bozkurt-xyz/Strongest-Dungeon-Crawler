# UI Design Pass — theme, structure, feel

Status: **brainstorm.** Nothing here is decided until the open questions at the bottom are answered.
Runs after `menu-staging.md`, which fixes how large panels are on screen.

## Why

The React migration was deliberately a port (R12, R15): every panel does what it did, built from
shared primitives, and none of them was designed. They read as MVP — flat translucent purple boxes,
thin type, a lot of dead space (the inventory is a 6.5-stud panel holding one row of nine slots),
no motion beyond a fade, no sound, and no item icons at all (every item def has `icon = ""`).

The goal of this pass is a UI with a point of view: a theme that means something in this game, a
structure that uses its space, and a feel — motion, response, sound — that makes it satisfying to
touch.

## Theme directions

The codebase already leans one way: the menu's home view is the **System** panel and the only theme
is named `SoloLeveling`. That points at direction 1, but it is worth choosing on purpose.

### 1. The System — holographic, light not material *(recommended)*

The UI *is* the System: an interface projected for the player alone. Panels are made of light rather
than material.

- **Surfaces:** near-black navy, highly translucent; edges drawn as thin bright strokes and **corner
  brackets** rather than full borders; faint grid or scanline texture; glow instead of shadow.
- **Colour:** one electric blue/cyan carries everything interactive; amber/red reserved for System
  alerts and danger; rarity colours as the only other hues. Today's palette is purple-led — this
  direction moves it to blue.
- **Type:** condensed sans, uppercase labels with tracking, tabular numerals for every value that
  ticks.
- **Motion:** panels *materialise* — brackets snap out, the frame draws, content staggers in with a
  brief flicker — and dematerialise faster than they arrive. Hover pushes an element slightly toward
  the camera, which only a world-space UI can do.
- **Voice:** System messages as notifications — `[ITEM ACQUIRED]`, `[LEVEL UP]` — with a chime.

Strong fit for world-space panels: light reads well over any background, and translucency is the
point rather than a compromise.

### 2. Grimoire — dark fantasy, weight not light

Classic ARPG (Diablo, Path of Exile): engraved metal, parchment, gold trim, serif display type.
Motion is physical — slide, settle, thud. Richest *dungeon* feel, but it fights world-space
translucency, and it needs textures, which means a real asset-production cost.

### 3. Tactical minimal

Flat, crisp, one accent, generous whitespace (Destiny-adjacent). The most legible and the cheapest to
build, and the least character.

A hybrid is plausible: the System's light language, with dungeon grit in the texture and the sound.

## Surfaces

### Always-on — highest priority

These sit over live gameplay, so they have to be legible against anything and must not compete with
combat.

- **StatusPreview.** A floating card beside the character is the least convincing surface right now.
  Options: (a) keep it diegetic but shrink it to a slim arc or band that hugs the character,
  (b) move vitals into screen space beside the skill bar, where players look anyway,
  (c) diegetic only while values change, fading to nothing at full health.
- **Loot.** One list panel over the nearest drop works, but the ARPG-native answer is **per-drop
  ground labels**: every drop gets its own rarity-coloured name plate above it, the selected one
  expands with the key hint, and a busy pile fans out to avoid overlap. It reads at a glance where
  the loot *is*, not just what it is. Bigger change; worth it if the game leans into loot.
- **Skill bar.** Already the most polished surface. Needs the theme pass, a clearer active state, and
  a proper ready/cooldown-end pulse.

### Menus

Inventory, Equipment, System and ItemInspect, staged by `menu-staging.md`. Structural work, beyond
skinning:

- Inventory should be sized by its content: a dense grid that fills, with category filtering that
  feels instant, not a wide panel with one row.
- Equipment pairs naturally with the character in frame (menu-staging D1(c)).
- ItemInspect becomes the hover card that R14 wants — design it as a tooltip from the start.
- View switching (System ↔ Inventory ↔ Equipment) should be a transition, not a cut.

### Feedback

Damage numbers, overhead HP, pickup confirmation, level-up and error toasts. Most of the *feel* of a
UI lives here rather than in the panels.

## Foundations

These come before any surface gets redesigned, or every surface invents its own.

- **One pixel density.** Panels currently use 200, 300 and 400 px/stud, so the same `TextSize` is a
  different physical size on each. Once staging fits panels to the view, set `pixelsPerStud` so one
  canvas pixel is about one screen pixel at 1080p, and design in screen pixels everywhere.
- **Type scale** — 5-6 steps, with a role for every one, plus tabular numerals. `Enum.Font` has to
  move to `FontFace` to get weights.
- **Spacing scale** — a 4/8 grid in canvas pixels, used by every primitive.
- **Colour roles** — the existing semantic layer (R2), re-derived from the chosen direction. Rarity
  colours join the theme as their own role group instead of living in `selectors/rarity`.
- **Elevation** — expressed as light (glow, stroke brightness), not drop shadow, if direction 1 wins.
- **Motion tokens** — 3-4 durations, 2-3 easings or spring presets, and a stagger step. Every
  animation picks from these.
- **Sound set** — open, close, hover tick, confirm, error, and pickup by rarity.
- **Icons** — an item icon pipeline. Studio MCP can generate textures and upload images, so a
  consistent generated set is an option worth testing before commissioning art.

## Motion — the engineering prerequisites

- **A motion primitive.** Guardrail 6 ("no motion library until a panel needs one") is now
  triggered. Spike two options against one real interaction: Ripple (springs, framework-agnostic),
  versus a small in-house `useSpring` built on React bindings. Bindings matter either way — animation
  must not re-render the tree each frame.
- **Exit animations are currently impossible.** `UIRuntime` renders `nil` the moment a panel is
  hidden, then fades an empty surface. Hosts need to keep rendering through the hide — pass a
  `visible` prop and unmount after the exit completes — before any dematerialise effect can exist.
- **Camera transition** from menu-staging D3 uses the same primitive.

## Process

1. **Pick a direction** (open questions below).
2. **Style tile.** One static specimen surface in Studio — palette, type scale, a button, a slot, a
   bar, a panel frame, one motion sample — iterated over MCP screenshots until it feels right. Cheap
   to change, and it settles the arguments before any panel is rebuilt.
3. **Rebuild tokens and primitives** to the style tile.
4. **Two hero surfaces to full polish**, motion and sound included: one always-on (loot) and one menu
   (inventory). These set the bar.
5. **Roll out** to the remaining surfaces.
6. **Feel pass** — view transitions, notifications, feedback, sound balance.

**Tooling first:** a dev command that opens any view with fixture data — seeded inventory, synthetic
loot drops, set vitals — and pins the camera, so every screenshot is reproducible without playing
into the state. This is what makes MCP iteration fast instead of fiddly.

## Decisions (2026-10-24)

1. **Direction: the System.**
2. **Purple is not identity** — the palette is free to move to blue.
3. **Skins are a future product.** Panels will eventually take optional, possibly purchasable styles
   that change the look heavily — border textures, frame treatments, ornaments — though not a genre
   switch. This shapes the foundations now: a theme can no longer be only colours and fonts. Panel
   chrome (frame, corners, header, dividers, slot frame) has to be a themable *part* — a skin can
   swap the frame component or its 9-slice textures, not just recolour it — and panel content must
   never draw its own chrome. Per-panel skins mean a theme is resolvable per surface, which
   `mountPanel`'s per-root `ThemeProvider` already allows.
4. **Loot: per-drop ground labels, collapsing into a list past a threshold.** Few drops show as
   labels where they lie; a big pile (late game, PoE-style mass kills) switches to the list so
   everything nearby is readable at a glance. The threshold, and whether it counts drops in range
   or overlapping labels, is a tuning question.
5. **HUD feel: Fisch.** Simple and minimal for the screen-space HUD. This is a reference for HUD
   restraint, not for the world panels.
6. **Menu camera: per view** (menu-staging D1(c)), to be revisited after playtesting.
7. **Icons: placeholder glyphs** — rarity-tinted, one shape per category — until the game outgrows
   the concept stage. Commissioned art comes much later.
8. **Vitals: a hybrid.** Screen UI that follows the character (constant size, on top, camera-facing,
   show-on-change), not a world panel — a world surface is depth-tested, lit, foreshortened by orbit
   and scaled by zoom, all of which hurt a glanceable bar in fast combat. Pinned above the skill bar
   is the same component in another position mode.

## Progress

**Engineering prerequisites — done.**

- **Exit animations.** `PanelHost.present(element, visible)` keeps a hiding panel rendered until its
  fade completes, then drops the subtree. Components receive `visible`; `useHeldWhileHidden` holds the
  last shown value through the exit (used by loot and item inspect, whose data is what disappears).
- **Motion primitive: in-house springs, not a library.** `hooks/useSpring(target, spec, from?)` returns
  a binding (no re-render per frame), keeps velocity when retargeted, only connects Heartbeat while
  moving, and returns `snapTo` for replaying an entrance. Presets live in the theme
  (`theme.motion.snap/settle/drift`, validated at startup like colours), so a skin can carry its own
  feel. Ripple was the alternative; the hook is ~100 lines and avoids a dependency.

**Style tile v2 — awaiting direction feedback.** `ui/dev/StyleTile.luau`, shown in place of the
System panel's content by F7 or "Tile" in the F6 tuner. Palette, type, chrome (corner brackets,
header rule), slots with rarity-lit floors, buttons, segmented gauges, and a looping materialise.

Findings while building it:

- **Pixel density is the first foundation problem.** At current staging the System panel's 1296px
  canvas spans ~775 screen pixels, so one canvas pixel is ~0.6 screen pixels and 13px text renders
  near 8px. The tile is authored in logical pixels at 1/1.5 scale and scaled up, so its sizes are what
  the player sees. The real panels need the same treatment (or a lower `pixelsPerStud`) before any
  type scale means anything.
- **Fonts.** Built-in families that fit: Michroma (display), Titillium Web (body, has weights),
  Roboto Mono (numbers), Sarpanch/Zekton as alternates. Use `Font.fromEnum`; guessed family JSON
  paths fail to load.
- **Chrome must never be a child of a padded container.** `UIPadding` applies to every child, so
  corner brackets placed beside padded content were pushed inward onto the text they frame. A chrome
  part owns the outer frame; content goes in its own padded body. Bake this into the skinnable
  `PanelFrame` so no panel can get it wrong.
- **Perspective shrinks the far edge.** With the panel turned toward the character, the camera sees
  its left edge 8.1 studs away and its right edge 5.5: left-edge text renders at ~68% the size of
  right-edge text (`faceCamera` 0.10). Raising `faceCamera` trades diegetic angle for evenness —
  0.40 gives 79%, 0.70 gives 87%. The type scale has to be set by the far edge, and fine print
  belongs on the near side.
- **F7 arrives with `gameProcessed = true`** (a core binding claims it), so dev keys that use it must
  guard on `GetFocusedTextBox()` instead.

**System theme — live (2026-10-25).** The style tile was approved and is now the default theme.

- `themes/ThemeBuilder` turns a small palette into a full theme; `System` (cyan) is the default and
  `SystemViolet` (the old purple) is the first alternate skin, proving a palette alone makes one. The
  contract gained `face` (Font objects), `type` (logical-pixel scale), `rarity`, and `chrome`
  (bracket specs, edge and fill transparency), all validated at startup.
- Chrome is now a component: `components/Brackets` and `components/PanelFrame`. `PanelShell`,
  `Header`, `Slot`, `Button` and `Tabs` were restyled in place, so every panel took the System look
  at once. Selectors emit rarity *keys*; components resolve them through `theme.rarity`.
- **Pixel density, solved generally.** A surface may declare `logicalWidth`: PanelHost keeps the full
  canvas (sharp text) and scales a root frame so the panel is authored in logical pixels close to
  screen pixels at staging. React clears its container's children on first render, so the UIScale
  lives one level above the frame React mounts into.
- **Inventory rebuilt** at `logicalWidth = 768` on the theme type scale. The other panels are
  re-skinned through the shared primitives but keep their canvas-pixel layouts until rebuilt.
- **Item inspect rebuilt** at `logicalWidth = 340` (measured: the card spans ~340 screen px at
  staging). The icon well is a slot enlarged — small brackets and a rarity-lit floor — and values are
  mono. "Inspect" in the F6 tuner opens it on the first bag item.

Findings from the inspect rebuild:

- **`UITextSizeConstraint.MaxTextSize` ignores UIScale.** The cap is in canvas pixels, so on a
  logical-scale panel a cap of 12 became 8 logical px. Buttons on logical panels take a fixed
  `textSize` instead of scaled text.
- **Titillium reads small.** It is narrow with a short x-height: 16 screen px of it reads like ~11 px
  of a typical UI face. Values moved to mono; if body text still feels small in play, raise
  `type.body`/`type.small` in the builder rather than per panel.
- **Set `logicalWidth` from a measurement**, not the intended size: read the surface's on-screen
  width from a screenshot at staging.

**Vitals HUD — live.** The StatusPreview world panel is gone; `panels/VitalsHud` replaces it as
screen UI (decision 8). The panel keeps the hand-built one's elements -- icon, caption, gauge and
current/max per vital, a stamina ring -- redrawn as a slim 340x58 strip in the System chrome, with
the style tile's segmented gauges (`components/SegmentedGauge`; HP trails the cells a hit took).

- Placed to the character's right at its projected position (beside the HumanoidRootPart, along the
  camera's flattened right vector, eased), so it keeps one size, never turns with the camera, and
  draws over effects. Falls back to pinned when the camera is inside the character.
- Fades in when any vital drops below full and out `lingerSeconds` after all are full; hidden while
  the menu is open. The screen edges pulse red under 30% HP.
- `VitalsHudConfig.anchor` is `"character"` or `"pinned"` (above the skill bar), toggled live by
  "Vitals" in the F6 tuner. Meant to become a player setting.
- Dev: `ServerStorage.DevPool:Fire(player, "Health", -40)` moves a pool from MCP or the command bar.

Findings:

- **Keep a panel's elements when restyling it.** A first pass cut the status panel down to bare bars
  and read as a regression; the System chrome and a slimmer shape were welcome, the lost icons,
  readouts and stamina ring were not.
- **The skill bar was not centred**: its authored 290px width was a minimum, leaving three slots
  left-aligned inside it. It now sizes to its slots.

**System panel rebuilt** at `logicalWidth = 768`, the same surface and scale as the inventory, using
the whole surface rather than the old inset card. Left: level/class/title, the vitals (the HUD's
`components/VitalsBlock`), combat stats. Right: attributes with the points to spend (each row is its
button; a `+` marks it), recovery stats. Every element of the hand-built panel is kept; the combat
and recovery stats were replicated all along and are now shown. `components/StatList` is the shared
section/row used here and by the inspect card. Percent stats were shown x100 (crit 5 as "500%") --
they are stored as percentage points.

- **Perspective slopes rows.** The staged panel's right side is nearer the camera, so lower rows
  slope downward to the right and a far-right value lines up with the next row's label. Stat rows
  are kept short (250px) and alternate rows are banded so the eye can follow a row.

**Equipment panel rebuilt** at `logicalWidth = 600`: title row with the equipped count, the
paper-doll (same column structure and socket proportions), then a headed candidate grid sized like
the inventory's. Empty sockets show a dim glyph of what belongs in them (`Slot.placeholderGlyph`).
All four menu panels are now on logical scale.

**Loot labels — live** (decision 4). `panels/NearbyLoot` gives each drop in range a name plate --
glyph and name in its rarity colour, stack count, and on the selected plate corner brackets and the
pickup key -- as screen UI projected above the drop, so plates keep one size and draw over effects.
Overlapping plates stack upward in distance order with a hairline down to their drop. Past `WorldLootInspect.labels.limit` (5) the pile collapses into a
list over the nearest drop -- the same screen-space treatment, rows drawn with the plates'
`LootLine`, scrolling past `maxVisibleRows` with the selection kept in view. The old world list
panel (WorldLootInspectPanel) is gone. Selection, hover and pickup go through LootClient for both.

- Dev: `ServerStorage.DevDrop:Fire(player, 3)` drops the first bag items in front of the player.
- **A scale-sized child of an `AutomaticSize` frame feeds back into its size** -- the selected
  plate's brackets stretched it across the screen. Chrome over an auto-sized element is a sibling
  sized from its measured `AbsoluteSize`.
- **Drops no longer stack into a column.** The server's ground probe hit earlier drops, so each
  landed on the last; drops are now excluded from it and scattered within `dropScatterRadius`.
- **Cycling is the mouse wheel over the loot UI, not keys.** The arrow keys also moved the
  character, and any key that changes meaning near loot fights combat and spends a scarce bind. The
  wheel over a plate or row (with precision focus held, like hover and click) steps the selection;
  the engine marks that wheel as processed, so the camera does not zoom. E is the only loot key.
  Plates stack in distance order only, so a selection change never slides another plate under the
  cursor.

**Menu motion — rigid, not floaty.** Panels switch on rather than fade, and every transition is a
fixed duration eased to a hard stop (`shared/ui/Ease`, `theme.transitions`); springs stay for hover
and readouts only, and `settle` lost its overshoot.

- **Open** (0.24s): a line of light draws out from the panel's centre, splits in two, and the pair
  open outward revealing the panel (expo-out), then dim away.
- **Close** (0.14s): the band collapses to the line (quart-in), the line shrinks to nothing.
- **Switch:** the outgoing panel closes and the incoming one opens `switchDelay` (0.08s) later, so it
  reads as one then the other rather than two fades crossing.
- **Camera:** a fixed-time move to the view's pose and a matching return on close (menu-staging.md).
- PanelHost owns this: a clip band inside the CanvasGroup with the full-size canvas centred in it, so
  the panel is revealed in place rather than squashed, and two scan-line frames at its edges.

**Placeholder icons — live** (decision 7). `glyphs/ItemGlyphs` holds 21 line-art glyphs as point
lists (weapon kinds, offhands, armour pieces, jewellery, flask, gem, scroll, box) and picks one per
item from its weapon class, offhand type, equipment class or category. `components/Glyph` draws them
with Path2D, so they are thin strokes of light with no assets. Slots, the inspect card and loot rows
show them in the item's rarity colour whenever an item has no `icon`.

## Open questions

None outstanding.
