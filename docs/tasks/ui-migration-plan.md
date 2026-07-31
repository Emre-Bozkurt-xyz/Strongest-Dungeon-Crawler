# UI Migration Plan — Studio instances to React-lua

## Goal

Move all UI out of Studio and into React-lua components. The filesystem becomes the source of truth,
so UI can be read, diffed, reviewed and edited like every other system in this repo.

Two problems drive this, and they are not the same problem:

- **Legibility.** Studio-authored instances are invisible outside Studio. Sharing one means either
  hand-transcribing a tree or dumping a 260 KB `.rbxmx` for a panel whose real content is ~110
  instances of structure.
- **Interactivity.** The current runtime layer synchronises state to UI by hand: a system pushes an
  update, a runtime works out which nodes changed, then walks and mutates them. That middle step is
  the entire reason `SlotVisuals` exists, and it is the part that was painful to write. It also
  scales badly precisely as the UI gets more interactive, which is the direction this is going.

A code-based tree builder was designed and rejected — see R1. It solves legibility and leaves
interactivity untouched.

Non-goal: rigs, world geometry, and meshes stay Studio-authored. Those need *reads*, not writes —
see "Deferred".

## Current state

Measured 2026-07-30.

### UI instance counts (`docs/ui/` exports)

| Export | Instances | Notes |
| --- | --- | --- |
| `SystemPanel` | 142 | largest |
| `EquipmentPanel` | 113 | on Studio stylesheets |
| `StatusPreviewPanel` | 50 | colour-divergent from the rest |
| `Design` | 45 | the stylesheet system itself |
| `InventoryPanel` | 43 | |
| `ItemInspectPanel` | 35 | **pilot** |
| `SkillSlotContainer` | 30 | |
| `WorldLootInspectPanel` | 29 | on Studio stylesheets |
| `OverheadHPBar` | 17 | |
| `HUD` | 3 | lives directly under `StarterGui` |
| `DamageLabel` | 2 | |

**~509 instances total.** No single panel is large; XML size is serialization overhead, roughly
2.3 KB per instance.

Locations differ: `HUD` sits under `StarterGui`, the rest under `Assets` and subdirectories. World
panels resolve via `PanelTemplateSchema.templatePath`.

### UI code today

**6,334 lines** across `src/client/ui/`. The panel runtimes are the bulk:

| Module | Lines | Fate |
| --- | --- | --- |
| `menu/MenuRigRuntime` | 603 | **keep** — world-space rig motion |
| `runtime/ItemInspectRuntime` | 596 | replace |
| `runtime/SystemPanelRuntime` | 507 | replace |
| `runtime/WorldLootInspectRuntime` | 476 | replace |
| `runtime/InventoryMenuRuntime` | 463 | replace |
| `runtime/EquipmentPanelRuntime` | 404 | replace |
| `DamageNumberController` | 382 | later — transient, imperative |
| `controllers/LootClient` | 363 | keep (logic, not UI) |
| `controllers/OverheadHealthBarController` | 329 | replace |
| `runtime/EquipmentMenuRuntime` | 281 | replace |
| `menu/MenuReducer` + `MenuStateStore` | 252 | **keep** — becomes the store React subscribes to |
| `runtime/SlotVisuals` | 194 | **delete** — exists only to hand-sync state to nodes |
| `runtime/PanelTemplateResolver` | 62 | **delete** |
| `runtime/PanelBinder` | 56 | **delete** |
| `shared/ui/PanelTemplateSchema` | 115 | **delete** |

Roughly **2,000–2,500 lines are replaced by markup** rather than rewritten.

### Store readiness

React subscribes to existing stores rather than owning state (R4). Audit:

| Store | Subscription | Action |
| --- | --- | --- |
| `MenuStateStore` | `subscribe() -> unsubscribe` | ready, ideal shape |
| `InventoryClient` | yes | ready, verify shape |
| `SkillMetadataClient` | yes | ready, verify shape |
| `CombatLoadoutMirror` | **none** — `get`/`set` only | add a change signal |
| `SkillPacer` | **none** — `get`/`set` only | add a change signal |

All three existing subscriptions return an unsubscribe function, which is what `useEffect` cleanup
requires. Their shapes differ (method vs function, three callback signatures), which is why R4 uses
per-store hooks rather than one generic `useStore`.

### The existing design system

`Design.rbxmx` holds a partially-adopted Studio Stylesheet setup. Only `EquipmentPanel` and
`WorldLootInspectPanel` are wired to it; everything else carries inline properties.

```
Design/
  Tokens                        7 colour tokens
  BaseStyleSheet                14 class-selector rules (element defaults)
  General/SoloLeveling          theme layer, derives Tokens, no rules yet
  EquipmentPanelStyle           .Background .Body .SlotContainer
                                .SlotBody { ::UICorner, ::UIPadding, :Hover, :Press }
                                .RarityFrame { ::UICorner, >.BackgroundImage }
  WorldLootInspectPanelStylesheet
                                .ListContainer { ::UIStroke }
                                .SelectionFrame { ::UICorner, ::UIStroke }
                                .Text
```

Decoded token values, to seed the theme:

| Token | Value |
| --- | --- |
| `Purple` | `Color3.fromRGB(46, 0, 115)` |
| `PurpleDark` | `Color3.fromRGB(36, 24, 53)` |
| `PurpleDarker` | `Color3.fromRGB(13, 0, 33)` |
| `Gray` | `Color3.fromRGB(92, 88, 94)` |
| `GrayDark` | `Color3.fromRGB(52, 49, 53)` |
| `GrayLight` | `Color3.fromRGB(160, 153, 163)` |
| `BlueLight` | `Color3.fromRGB(185, 206, 232)` |

The stylesheet model — tokens, roles, derives, pseudo-children, states — maps closely onto a React
theme context, so porting it is translation rather than redesign.

## Core design decisions

### R1. React-lua, not a custom tree builder

A custom builder (`TreeSpec` + `TreeMounter` + `Theme`) was designed first and rejected on merit,
not cost.

It solves legibility: the tree becomes code, diffable and themeable. It does **nothing** for
interactivity — after building it, panel runtimes still walk and mutate nodes exactly as today, and
all ~2,900 lines of them survive.

The decisive argument is where that path leads. Pursuing interactivity on top of a builder means
adding subtree re-mounting, then diffing, then state-to-prop binding, then list keys. That
terminates at a worse React, maintained in-house. Adopting a framework deliberately beats
reinventing one accidentally.

Accepted costs, both permanent rather than one-off:

- **A dependency not under our control.** react-lua is a third-party Roblox port of a JS framework.
  If it stagnates, we own a fork. This is the genuinely uncomfortable part of the decision.
- **Two paradigms, forever.** World-space motion stays imperative (R3), so the codebase runs
  declarative surface content alongside imperative world placement. Normal for Roblox React, but it
  does not go away.

### R2. Studio Stylesheets are dropped; theming moves to context

The alternative — keep trees in Studio and let stylesheets style them — was rejected along with the
builder. It leaves styling unreviewable and depends on a beta Studio feature.

Two layers, the first of which is the one usually skipped:

```luau
-- Layer 1: semantic tokens. No component names a raw Color3.
Theme.color = {
    surface     = Theme.raw.PurpleDarker,
    textPrimary = Theme.raw.BlueLight,
    textMuted   = Theme.raw.GrayLight,
    danger      = Color3.fromRGB(220, 84, 84),
}

-- Layer 2: roles composed from tokens.
Theme.styles = {
    BodyText = { TextColor3 = Theme.color.textPrimary, BackgroundTransparency = 1 },
    Card     = { BackgroundColor3 = Theme.color.surface },
}
```

`raw` holds the ported Studio tokens verbatim; `color` gives them semantic names. Delivered through
`ThemeProvider` / `useTheme`, so per-subtree overrides and a future second theme are free.

Studio's `::UICorner` / `::UIStroke` pseudo-children become ordinary child elements in a styled
component. Studio's `:Hover` / `:Press` states become component state.

### R3. React owns the SurfaceGui and below; nothing above it

The mount boundary is the `SurfaceGui`. React renders its children and never touches the
`WorldPart`, its CFrame, rig motion, or visibility animation.

```luau
local root = ReactRoblox.createRoot(surfaceGui)
root:render(e(ThemeProvider, { theme = Theme },
    e(ItemInspectPanel, { itemUid = uid })
))
```

This is a cleaner split than exists today, where panel content and world placement are tangled in
the same runtime files. `MenuRigRuntime`, `WorldPanelFollower` and `WorldPanelVisibilityAnimator`
stay imperative and unchanged.

### R4. React subscribes to existing stores; it does not own state

State stays where it is — `MenuStateStore`/`MenuReducer`, the client mirrors, `SkillPacer`. React
reads through one small hook per store:

```luau
local function useInventory()
    local snapshot, setSnapshot = React.useState(InventoryClient.getSnapshot())
    React.useEffect(function()
        -- The returned unsubscribe IS the effect cleanup. Without it the handler outlives the
        -- component, sets state on a dead tree, and the store leaks a closure per open/close cycle.
        return InventoryClient.onChanged(function()
            setSnapshot(InventoryClient.getSnapshot())
        end)
    end, {})
    return snapshot
end
```

A single generic `useStore` was considered and rejected: the stores have three different shapes
(`MenuStateStore:subscribe(prev, next, action)` as a method,
`InventoryClient.onChanged(ChangeContext)` and `SkillMetadataClient.onChanged(name, metadata)` as
functions), so a generic hook needs per-store adapters anyway. Per-store hooks put each store's
quirks in exactly one place and give components a clean typed API, without touching working store
code to normalise it.

All three existing stores return `() -> ()` unsubscribe functions — verified 2026-07-30. Signals
added to `CombatLoadoutMirror` and `SkillPacer` must match that contract.

This keeps the migration to the view layer. Moving state ownership into React as well would turn a
UI port into a state-architecture rewrite, and the stores are not the thing that hurt.

react-lua is a React 17 port, so `useSyncExternalStore` is not available and the hook above is the
correct pre-18 pattern. **Verify the exact hook surface of the pulled build before relying on
anything beyond the React 17 set.**

### R5. Name-based binding is deleted, not preserved

`PanelBinder` resolves nodes by name, which makes every node name load-bearing API — renaming one
silently breaks whichever runtime binds it. Under React, components hold their own children
directly, so names become cosmetic.

`PanelBinder`, `PanelTemplateResolver` and `PanelTemplateSchema` are deleted rather than ported.
This removes a whole class of breakage, and it is why converted panels must not try to keep the old
node names for compatibility (see Guardrail 2).

### R6. Animation stays imperative for now

react-lua ships no motion primitives. In-panel transitions use refs plus `TweenService`; world-panel
motion is untouched (R3).

No motion library (Ripple, Otter) until a panel actually needs interpolated state. Adding one is
additive, and picking it before there is a concrete case means guessing.

### R7. `StatusPreviewPanel`'s divergence is a role, not a palette

It is the always-on gameplay panel: visible beside the character whenever no major panel is open,
competing for legibility against arbitrary world backgrounds rather than against a dimmed backdrop.

So it is not styled differently because it is a different *thing* — it is styled differently because
it has a different *requirement*. That makes it `styles.AmbientPanel`: a role with stronger contrast,
heavier stroke, and higher background opacity, composed from the same tokens as everything else.

Its existing bespoke colours are dropped and it adopts unified styling. If legibility suffers in
play, the fix is to strengthen the `AmbientPanel` role — which then benefits every future always-on
surface — not to reintroduce a one-off palette.

### R8. Themes are parameterised from the start

Theme swapping is a live intention, so `ThemeProvider` takes a theme object and themes are values in
a registry rather than a single module-level table. `SoloLeveling` is treated as a real second theme
slot, not dead content.

The cost of parameterising now is near zero; retrofitting it after fifty components have imported a
singleton is not.

Practically: every component reads through `useTheme()`. No component requires `Theme` directly.

### R9. All UI is code-mounted; one persistent screen root plus one root per world surface

`HUD` lives under `StarterGui` today only so it could be live-edited in Studio. Once UI is code, that
reason is gone, so nothing is pre-placed — everything is created and mounted at runtime.

- **One persistent screen-space root**, created at startup under a code-created `ScreenGui`. Holds
  the HUD, damage numbers, and every cross-surface concern: drag previews, tooltips, modals.
- **One root per world surface**, created and destroyed by that surface's host alongside the
  `WorldPart` + `SurfaceGui`.
- A shared `mountPanel(surface, element)` helper wraps providers so context setup is not
  hand-duplicated.

A single root with `createPortal` into each `SurfaceGui` was the first choice and is rejected. The
decisive question is **who owns surface lifetime**, and here it is imperative code —
`MenuRigRuntime` creates, moves and destroys world panels. Portaling into instances React does not
control forces a two-phase teardown: the rig wants to `:Destroy()` the part, but React must drop the
portal first or it holds a destroyed Instance. That coupling fails intermittently and only under
timing, which is the worst kind of bug to inherit. Per-surface roots make teardown sequential and
obvious — `root:unmount()` then `surface:Destroy()`.

The argument originally made *for* a single root — shared context — is weak here. R4 keeps state in
external stores, so context carries only the theme, and duplicating a provider per root costs a few
lines in `mountPanel`. Per-surface roots additionally give error and render isolation for free.

Cross-panel interactions (dragging an item from inventory to equipment) are served *better* by this
split: the drag layer lives in the persistent screen root, where it needs to be anyway to float
above everything, and both panels dispatch to the same store.

### R10. Components render, hooks read, actions write

Replacing the runtimes is a redesign, not a transcription. What they currently do splits three ways:

| Runtime responsibility today | Under React |
| --- | --- |
| Bind nodes, walk and mutate them | gone — markup |
| Subscribe to stores | `use*` hooks (R4) |
| Handle input | event props on elements |
| Send commands to the server | `actions/` modules |
| Derive "what can I do with this item" | pure selector functions |

The residue worth keeping as real modules is the last two. Command senders and selectors are logic,
not view, and burying them in components makes them untestable and unreusable.

```
src/client/ui/
  app/          UIApp, root creation, portal host
  components/   shared primitives — Panel, Slot, Button, Text
  panels/       one folder per panel
  hooks/        useStore, useTheme, useInventory, useCombatLoadout
  actions/      command senders (equip, drop, split, use)
  world/        KEEP — WorldPanelFollower, WorldPanelVisibilityAnimator
  menu/         KEEP — MenuRigRuntime, MenuStateStore, MenuReducer, MenuOrchestrator
src/shared/ui/
  themes/       theme registry + tokens
```

### R11. Rewrite panels as components; do not port trees first

The Studio tree is a visual reference, not an input. Each panel is rewritten directly as components
in one step.

The rejected alternative — convert Studio trees to data specs, then convert specs to components —
is two conversions where one suffices, and the intermediate is throwaway.

### R12. Panels are redesigned, not reproduced

The existing UI was built quickly to get something on screen and is not a target to preserve. It is
missing polish and its structure is not the structure it should keep.

So a conversion is **not** a transcription. Each panel is an opportunity to restructure for better
UX, and `docs/ui/*.rbxmx` is reference for *what data a panel shows and what actions it offers* —
not a visual specification.

What is still guarded is **functional completeness**: the new panel does everything the old one did,
or the omission is deliberate and recorded in that panel's commit. Losing "split stack" because
nobody noticed it existed is the failure mode this prevents. Losing it on purpose is fine.

Consequence for sequencing: shared primitives (`Panel`, `Button`, `Slot`, `Text`, `ScrollList`)
matter more than they would in a faithful port, because they are what makes a redesign consistent
across nine panels instead of nine bespoke looks. They are built during the pilot, not deferred.

### R13. No compatibility layer; deleted code lives in git, not in the tree

Nothing is kept working "for now". A converted panel's old runtime, its Studio tree, and any binding
it depended on are deleted in the same commit that lands the replacement.

`docs/ui/*.rbxmx` stay as visual reference for panels not yet converted, and are deleted with the
last one. Git history is the archive; the running codebase carries no dead paths, no shims, and no
"legacy" branches in live code.

### R14. Target interaction model — deferred until every panel is ported

The intended end state for item interaction, recorded now so panels are not built in ways that
foreclose it, but **not built until R2–R4 are done** (R15).

- **Inspect becomes a hover tooltip**, not a panel. Hovering a slot summons a card for that item;
  it is a pure function of item data and can be summoned by any surface.
- **Holding a modifier expands the tooltip** into a comparison against whatever occupies that slot.
- **Click-carry to equip.** Click picks the item up onto the cursor, click places it. Explicitly
  *not* press-and-hold drag: these are world-space panels, and holding a button while sweeping the
  camera between two floating surfaces is awkward and loses the item if pointer contact breaks.
  Click-carry lets the player reorient freely mid-move. (PoE works this way; the "drag" recollection
  is inaccurate.)
- **Drop by carrying the item out of the panel**, or a dedicated key.
- **`InventoryPanel` stops rendering equipment.** Equipment display belongs to `EquipmentPanel`,
  which is where placing an item into a slot makes sense.
- **The carried item becomes a floating world-space mini panel**, inheriting the source panel's
  rotation and offset slightly toward the camera, so it reads as lifted off the surface and cannot
  clip into the panel it came from. Crossing to another panel would interpolate rotation toward the
  target's plane. A screen-space carried icon is the cheap alternative but discards the diegesis.

### R15. Port everything before reworking interaction; gate the rework on a pointer-input spike

Panels are ported to React first (R2–R4) with their existing interaction model, kept simple. Only
then is R14 attempted.

Sequencing this way keeps the port a port. Bundling a new interaction model into it would mean every
panel conversion is also an interaction redesign, with no way to tell which half caused a regression.

Before any R14 work begins, a **throwaway Studio spike must establish that world-space `SurfaceGui`
pointer input is reliable** — per-slot hover enter/leave, at the angles these panels actually sit,
while the character moves. The entire model rests on it.

If pointer input proves unreliable and there is no straightforward workaround, **R14 is dropped**
rather than worked around. The ported panels stand on their own; R14 is an enhancement, not a
completion.

### R16. Orchestration: `PanelHost` replaces the plugin layer; the world-motion stack is untouched

Verified by reading `MenuRigRuntime` and `WorldGUIManager` before designing (2026-07-30).

**What the existing stack actually does — better factored than expected:**

- `WorldGUIManager` (1029 lines) owns panels **by name**: `registerPanel({ name, part, group, … })`,
  `setPanelVisibility(name, visible, duration, parent)`, follow modes, groups, tweens. It is handed
  a `BasePart`; it does not create one.
- `MenuRigRuntime` (603 lines) **never touches instances**. It keeps menu state locally, computes a
  target position per panel id, and registers those as override providers via
  `wgm:setPanelTargetOverrideProvider(panelId, fn)`. A pure positioning brain keyed by id.
- The **panel runtimes** are what create/resolve a part and call `registerPanel`.

So the integration point is `registerPanel`, and the earlier concern that the rig would have to
"learn about" code-created surfaces was unfounded — it already works purely by id and never
discovers instances.

**Both `WorldGUIManager` and `MenuRigRuntime` need zero changes.** ~1,600 lines of world-motion
machinery is preserved exactly as-is.

`PanelHost` therefore takes precisely the role the runtimes held:

```
create WorldPart + SurfaceGui in code
wgm:registerPanel({ name = id, part = worldPart, group = ..., followMode = "player", ... })
mountPanel(surfaceGui, component)          -- per-surface React root (R9)
-- on visibility change:
wgm:setPanelVisibility(id, visible, 0.2, workspace)
```

**Lifecycle: create lazily on first show, then keep alive.** `setPanelVisibility` takes a `parent`
and reparents rather than destroying, so the existing machinery already assumes panels persist.
Destroying on close would fight the fade-out, which needs the part to survive the animation. To stop
hidden panels re-rendering, the host renders `nil` in place of the component when hidden: the root
and surface stay alive so animation still works, but the subtree drops.

**What replaces the plugin layer.** A `PanelPlugin` exists to *push* state into a dumb runtime, and
React components *pull*, so most of each plugin evaporates. `ItemInspectPanelPlugin` is
representative: `setInspectState` disappears entirely, `shouldShowInspect` becomes a predicate in
the registry, and `resetFollow`/`setVisible` stay imperative on the world stack.

```
app/PanelRegistry   data: { id, component, tier, isVisible(state), surface = { size, group, ... } }
app/PanelHost       owns one surface: create part, register with WGM, mount root, toggle visibility
app/UIRuntime       subscribes to menu state; ensures the right hosts exist and are visible
```

`MenuOrchestrator` narrows to its intent API (`open`/`close`/`setView`/`setInspect`/…), which is
already good; its plugin-lifecycle half moves to `UIRuntime`. `MenuStateStore`, `MenuReducer` and
`MenuInputBridge` are unchanged.

Deleted: `PanelPluginRegistry`, `PanelPluginTypes`, all eight plugins (~550 lines).

**Panels are presentational; containers read state.** `ItemInspectPanel` taking a `uid` prop was
wrong — something would have to push the uid in, which is the pattern being deleted. Split instead
into `ItemInspectCard(props: { uid })` presentational and a thin `ItemInspectPanel()` container that
reads `useMenuState().inspect`. The card is then directly reusable as the R14 hover tooltip, which
takes an arbitrary item rather than the menu's inspect state.

## Phases

### Phase R0 — Foundations
- [x] Add `react` and `react-roblox` via Wally — `jsdotlua/react@17.2.1`, 17 packages
- [x] Confirm Rojo maps `Packages/` into the tree — already mapped to `ReplicatedStorage.Packages`
- [x] Verify the hook surface: `useState`, `useEffect`, `useContext`, `useMemo`, `useCallback`,
      `useReducer`, `useRef`, `useBinding`. **No `useSyncExternalStore`**, confirming R4's assumption.
      `ReactRoblox` provides `createRoot`, `createLegacyRoot`, `createPortal`
- [x] `src/shared/ui/themes/` — `SoloLeveling` ported from `Design`, registry with startup validation
      that every theme fills every colour and role (R8), including `AmbientPanel` (R7)
- [x] `ThemeContext` — `Provider`, `useTheme`, `useStyle(role, overrides)`
- [x] Per-store hooks: `useMenuState`, `useInventory`, `useCombatLoadout` (R4)
- [x] `useSkillCooldown` — see deviation below
- [x] `ScreenRoot` — code-created `ScreenGui`, persistent screen-space root (R9)
- [x] `mountPanel(container, element, theme?)` — per-surface roots wrapping providers (R9)
- [ ] `actions/` module scaffold — deferred to R1, where the first real commands appear

**Deviation 1 — no change signal on `SkillPacer`.** Its state is time-derived
(`cooldownStartAt` + `cooldownDuration`), so there is no "changed" moment to subscribe to; the value
differs on every frame it is visible. `useSkillCooldown` returns a **React binding** driven by
`Heartbeat` instead. A binding writes the property directly without re-rendering, so a cooldown
sweep does not reconcile the subtree every frame for every skill on the bar.

**Deviation 2 — no change signal on `CombatLoadoutMirror`.** `InventoryClient` holds the loadout
itself, writes the mirror, and only then fires `onChanged` carrying the loadout. The mirror is a
downstream cache with no independent truth, so a signal on it would be a second notification path
for data that already has one. `useCombatLoadout` subscribes to `InventoryClient` and filters for
`loadout`/`snapshot` changes. The mirror remains for synchronous reads from skill code.

### Phase R1 — Pilot: ItemInspectPanel (35 nodes)
Smallest panel with real interactivity and a pending feature request. This is where conventions are
invented, so it is done deliberately and not delegated.

Kept **simple** — a compact card with grouped sections, keeping the existing click-button
interaction. No hover, no comparison, no carry; those are R14 and wait for every panel to be ported
(R15). The improvement over today is structure and hierarchy, replacing a flat list of text lines.

- [x] Shared primitives in `components/`: `Panel`, `Text`, `Button`, `ScrollList`. `Slot` deferred to
      `InventoryPanel`, which is its first real consumer
- [x] `actions/ItemActions` — equip, unequip, use, drop, plus `pickEquipSlot`
- [x] `selectors/itemInspect` — pure view-model builder, replacing the flat `addLine` list
- [x] `hooks/useAttributes` — needed for met/unmet requirements
- [x] Build the panel: rarity-tinted header, weapon / charges / affixes / base stats / requirements
      sections, action bar
- [x] Capability checklist (below)
- [x] `app/PanelRegistry`, `app/PanelHost`, `app/UIRuntime` (R16)
- [x] Split into `ItemCard` (presentational) + `init` (container reading `useMenuState`)
- [x] Wired: `UIRuntime.start()` in `Bootstrap`, `ItemInspectPanelPlugin` unregistered
- [ ] Verify in Studio
- [ ] Delete `ItemInspectRuntime` (596 lines), `ItemInspectPanelPlugin`, and the Studio tree

#### Capability checklist vs `ItemInspectRuntime`

| Capability | Status |
| --- | --- |
| Icon, display name, rarity | kept; name is now rarity-tinted rather than a separate label |
| Requirements (level / stats / attributes) | kept and improved — met/unmet colouring, current value shown |
| Base stats | kept |
| Affix modifiers | kept |
| Equip / Unequip / Use / Throw | kept, with identical availability and lock-flag rules |
| Empty state | kept |
| Generic meta key/value dump | **dropped deliberately** — unordered, unformatted internal keys; debug output rather than player information |
| Item charges | **kept explicitly.** Previously visible only via the meta dump, so dropping that would have silently lost it. This is what the checklist is for |
| Weapon damage / attack speed / crit | **new** — the old panel never surfaced these despite the data existing |

**Deviation from R12's "no comparison":** none. Comparison stays with R14.
- [ ] **First real feature through the new path:** colour unmet equip requirements red, using the
      `danger` token
- [ ] Surface the equip rejection reason — `RequirementEvaluator` already returns
      `requirement_failed::Strength`, it just never reaches the client

### Phase R2 — Small panels
Exercise the patterns before meeting the big trees.
- [ ] `DamageLabel` (2), `HUD` (3), `OverheadHPBar` (17)
- [ ] `WorldLootInspectPanel` (29) — second stylesheet consumer, first real theme port
- [ ] `SkillSlotContainer` (30)

### Phase R3 — Inventory and equipment
The list-heavy panels; where keys and memoisation start to matter.
- [ ] `InventoryPanel` (43)
- [ ] `EquipmentPanel` (113) — primary stylesheet consumer
- [ ] Extract a shared `Slot` component; delete `SlotVisuals` (194 lines)

### Phase R4 — Remaining
- [ ] `StatusPreviewPanel` (50) — adopts unified styling via the `AmbientPanel` role (R7); its
      bespoke colours are dropped
- [ ] `SystemPanel` (142)
- [ ] `DamageNumberController`, `OverheadHealthBarController` — transient/imperative, evaluate
      whether React helps at all

### Phase R5 — Pointer input spike
A throwaway script, not production code. Gates R6 (R15).
- [ ] Do world-space `SurfaceGui`s receive reliable per-slot hover enter/leave?
- [ ] Does it hold at the angles panels actually sit, and while the character moves?
- [ ] Is the pointer→slot mapping stable enough to carry an item between two panels?
- [ ] **If no, and no straightforward workaround exists: drop R14 and stop here.** The ported panels
      stand on their own.

### Phase R6 — Interaction rework (conditional on R5)
Only attempted if the spike succeeds. Each step is independently useful, so this can stop partway.
- [ ] Hover targeting: which slot is under the pointer, and tooltip placement relative to it
- [ ] Inspect becomes a hover tooltip (R14)
- [ ] Modifier-held comparison against the occupying item
- [ ] Click-carry equip: carried state, valid targets, rejection feedback
- [ ] `InventoryPanel` stops rendering equipment (R14)
- [ ] Carried item as a floating world-space mini panel (R14) — the most speculative piece; a
      screen-space carried icon is the fallback

### Phase R7 — Retire the old layer
Mostly bookkeeping if R12 is followed — each panel's old code dies with its conversion.
- [ ] Delete `PanelBinder`, `PanelTemplateResolver`, `PanelTemplateSchema` (R5)
- [ ] Delete the Studio-authored trees and `Design`
- [ ] Delete `docs/ui/*.rbxmx` (R12)
- [ ] Confirm nothing under `StarterGui` is pre-placed (R9)

## Guardrails

1. **A converted panel must match the old one's *capabilities*, not its appearance** (R12). Before
   deleting a panel, list what it could do and confirm the replacement does each, or record the
   omission deliberately. Visual fidelity is explicitly not required.
2. **Do not preserve old node names for compatibility.** Binding by name is being deliberately
   deleted (R5); keeping the names invites something to depend on them again.
3. **No raw `Color3` in a component.** Colours come from `useTheme`. A component needing a colour the
   theme lacks means the theme needs a token.
4. **State stays in existing stores** (R4). If a panel wants to own state React-side, that is a
   deliberate decision recorded here, not a drive-by.
5. **Lists get keys.** An inventory grid without stable keys re-renders every slot on every change.
6. **No motion library until a panel needs one** (R6).
7. **React never touches anything above the SurfaceGui** (R3).
8. **A converted panel's old runtime and Studio tree die in the same commit** (R12). No shims, no
   "legacy" paths kept alive.
9. **No component requires a theme module directly** — always `useTheme()` (R8).
10. **Command sending and selectors live in `actions/` and pure functions**, not inside components
    (R10).

## Open questions

None currently blocking. Resolved so far:

- Store subscription shapes — all three return `() -> ()`; hooks are per-store (R4).
- Root topology — persistent screen root plus per-surface roots (R9).

## How to add a panel

The whole procedure, once R1 landed. `ItemInspectPanel` is the worked example to copy.

**1. Write the components** under `src/client/ui/panels/<PanelId>/`.

- `init.luau` is the container: reads state via hooks, renders the presentational part. No props.
- Any presentational component takes plain props and is ignorant of *why* it is being shown.
- Build from `components/` primitives. Add a primitive only when a second panel needs it.

  | Primitive | Use for |
  |---|---|
  | `PanelShell` | **Start every menu panel with this.** The backdrop/body/gradient/padding chrome that every Studio panel repeats identically. Its children are the panel's blocks, stacked by `LayoutOrder`. |
  | `Header` | Bordered title bar with the glowing title. |
  | `Panel` | A bordered block inside a panel (`role = "PanelBlock"`, `stroke = true`). |
  | `ScrollList` | Vertical stack that scrolls. |
  | `Grid` | Fixed-cell scrolling grid, for slots. |
  | `Slot` | One item slot: rarity tint, inset icon, stack count, gloss, click target. |
  | `Tabs` | Horizontal category strip. Controlled — the caller owns `activeId`. |
  | `Gauge` | Filled bar. Pass a binding for anything animating per frame. |
  | `Icon` | Aspect-locked image field. |
  | `Text`, `Button` | Leaves. |

  Exactly one child of `PanelShell` should carry `fill = true` (supported by `Panel`, `ScrollList`,
  `Grid`) to absorb the leftover height. The rest take scale heights.
- Read data with `hooks/` (`useInventory`, `useCombatLoadout`, `useMenuState`, `useAttributes`,
  `useSkillCooldown`). Never require a client store directly from a component.
- Derive display shape in `selectors/`, not in the component. Selectors are pure and testable.
- Send commands through `actions/`. Never build a request payload inline.
- Never write a raw `Color3`, `Font`, or `TextSize` — use `useTheme()` / a `role`. If a role is
  missing, add it to **every** theme (the registry asserts this at startup).

**2. Register it.** Which registry depends on whether it lives in the world or on the screen.

A **world panel** goes in `app/PanelRegistry.luau`:

```luau
{
    id = "InventoryPanel",              -- must match SharedConfig.UIMenu.panels and MenuRigRuntime
    component = InventoryPanel,
    surface = { width = 6, height = 5, pixelsPerStud = 120 },
    placement = menuRigPlacement("InventoryPanel"),
    isVisible = function(state)
        return state.modal.open and state.modal.view == "inventory"
    end,
}
```

`isVisible` is the old plugin's `shouldShow*` predicate, nothing more.

`placement` is passed straight to `WorldGUIManager:registerPanel`, so the host has no opinion about
where panels live. Use `menuRigPlacement(id)` for a panel on the menu rig; supply the table directly
for anything else (the status preview is character-anchored via `WorldGUIConfig`, not the rig).

If visibility depends on something other than menu state — nearby loot, a controller — add a `watch`:

```luau
watch = function(notify)
    return LootClient.onChanged(notify)   -- returns an unsubscribe
end,
```

`isVisible` then reads that source directly and ignores its `state` argument. Only that entry is
re-evaluated when the source fires.

A **screen-space element** goes in `app/ScreenRegistry.luau` instead, which is just `{ id, component,
zIndex? }`. There is no host, no placement and no fade: everything renders into the one persistent
`ScreenRoot` tree and decides for itself whether to draw. That asymmetry is deliberate — a world
panel's visibility is imperative because a *surface* must exist or not, while a screen element's is
an ordinary render decision.

**3. Unregister the old plugin** in `MenuOrchestrator.ensureInit`. Both paths registering the same
`WorldGUIManager` panel name would fight — the second `registerPanel` overwrites the first.

**4. Verify, then delete** the old runtime, its plugin, and the Studio tree, in one commit (R13).
Run the capability checklist first (Guardrail 1) — list what the old panel could do and confirm each,
or record the omission.

**What you never touch:** `WorldGUIManager`, `MenuRigRuntime`, `MenuStateStore`, `MenuReducer`,
`MenuInputBridge`. Placement, motion and menu state are already correct and stay imperative (R3,
R16). Panel placement is configured in `SharedConfig.UIMenu.panels[id]`, not in the panel.

### Reading the Studio exports

`tools/dump-rbxmx.ps1` prints any file in `docs/ui/` as an indented tree with the layout and styling
properties that survive porting, defaults omitted:

```
./tools/dump-rbxmx.ps1 -Path docs/ui/ItemInspectPanel.rbxmx
```

**Run this before converting a panel.** The tokens in `Design.rbxmx` are only half the design — the
per-panel styling (stroke weights and transparencies, gradients, layered surface translucency,
fonts, block proportions) is authored directly on the instances and is what gives each panel its
identity. Porting the palette alone produces a flat panel that is technically on-theme and looks
nothing like the original.

**Reproduce the container structure; do not flatten it to absolute positions.** The exports nest
blocks in columns with `UIListLayout` and lock shapes with `UIAspectRatioConstraint`, and that
nesting is what keeps a layout consistent — each element is sized against its own column rather than
against the panel. Flattening it to N absolutely positioned rectangles means N independently tuned
numbers that drift out of proportion the moment one is adjusted, and it reads immediately as
inconsistent sizing. `EquipmentPanel` was built that way first and had to be redone. R12 licenses
redesigning the *presentation*, not discarding the layout mechanics.

Screenshots are for judging overall proportion and hierarchy. They are perspective 3D captures, so
measuring pixel coordinates off them is a poor substitute for reading the container tree.

Stylesheet-driven rules are the exception: those live in base64 `PropertiesSerialize` blobs the
script does not decode, so a panel styled that way needs a screenshot to port faithfully.

### Traps

**`init.luau` collapses into its folder.** Inside `panels/Foo/init.luau`, `script` *is* the `Foo`
module, so `script.Parent` is `panels` and `script.Parent.Parent` is `ui`. A sibling file like
`panels/Foo/Card.luau` is a *child* of that module and needs one level more. Getting this wrong
produces `X is not a valid member of LocalScript "…Client"` at require time, not at build time —
`rojo build` will not catch it.

**The Luau LSP disagrees with Rojo about `init.luau`.** It resolves those requires as though the
file were a child rather than the collapsed module, so a correct require can show a false "Unknown
require". The runtime is authoritative; check the stack trace's reported script full name.

**Regenerate `sourcemap.json` after adding dependencies**, or every `ReplicatedStorage.Packages.*`
require shows a false error.

**`ClipsDescendants` does not clip rotated descendants.** Any masking effect built from a clipping
container must rotate something *other* than the clipped child — for the radial gauge that means
rotating the `UIGradient` rather than the Frame it sits on. The symptom is partial: the effect looks
correct wherever the unclipped content happens to coincide with its clip, and breaks everywhere else,
which reads like a maths error rather than a clipping one. See `RadialGauge`.

**Never trust the payload a store's change signal hands you — re-read the store.** Several client
stores publish through a `BindableEvent`, and BindableEvents deep-copy their arguments across the
Fire/Event boundary, **stripping metatables and functions**. `StatsClient` fires the live
`PlayerStats`, whose pools are objects with `getCurrentValue`/`getValue` methods; what arrives is a
lifeless copy with those methods gone. Any consumer guarding on `type(pool.getValue) == "function"`
then silently reads nothing, so the symptom is a section that renders fine on first paint and goes
*blank* on the first update — no error, because every guard did its job.

`useInventory` was immune only because it happened to re-read via `read()`. Do the same everywhere:
treat the signal as a bare notification. Note that re-reading usually returns a stable identity, so
`useState` will bail out of re-rendering — force it with a counter (`useReducer`), which is what
`useSyncExternalStore` would do if react-lua 17 had it. See `useStats`.

**Do not chain `AutomaticSize` inside `AutomaticCanvasSize` inside `UIFlexItem`.** Each layer asks
another for its size and Roblox resolves the cycle inconsistently. The symptom is not a crash or an
obviously broken layout — it is *drift*: two columns in the same row slowly diverging the further
down the list they are, which reads like a rounding bug. Compute the height explicitly at whichever
layer you control (see `Section` in `ItemCard.luau`, sized from its row count). One auto-sizing layer
is fine; the problem is stacking them.

**A faded-out world panel still absorbs pointer input.** `CanvasGroup.GroupTransparency = 1` hides a
panel visually but changes nothing about hit-testing, so a hidden panel parked over another one
silently eats every click aimed at the panel behind it. The symptom is not an error — it is clicks
that produce no logs at all, plus one working region wherever the hidden panel's rectangle happens
not to reach. `PanelHost` gates `SurfaceGui.Enabled` and `BasePart.CanQuery` on visibility for this
reason; any new surface owner must do the same.

Compounding it: `MenuRigRuntime._resolveOverrideTarget` returns nil for a panel absent from
`sidePanelIds`, so an inactive panel falls back to its `registerPanel` base offset rather than being
parked out of the way. Hidden panels sit wherever that offset puts them, often centred on the
primary panel.

## Delegation

R1 is deliberate work: it invents the conventions every later panel inherits — how components
compose, what belongs in `components/` versus a panel folder, the shape of `actions/`, which theme
roles are actually needed. Cheap to get right once, expensive to get wrong nine times.

R2–R4 are good delegation targets once R1 has produced an exemplar. "Here is the pattern, the hooks,
the primitives — convert `SkillSlotContainer`" is well-specified and verifiable.

UX decisions about what a panel *should become* are never delegated.

Note that a delegated agent starts without context and re-derives it, which can cost more than it
saves. This document plus one converted panel is what makes that cheap — the doc is load-bearing for
delegation, not only for tracking progress.

## Deferred

- **A unified client store layer.** There is a cleaner design than today's mix: one small `Store`
  primitive (`get`/`update`/`subscribe`), networking modules writing into stores rather than holding
  state, and derived data (the combat loadout) as a selector instead of a duplicated cache. It would
  collapse the per-store hooks into one generic `useStore`.

  Deferred because it touches `SkillsFramework` — skill code reads `CombatLoadoutMirror`
  synchronously — so it stops being a UI refactor and becomes a client-state refactor with the UI
  migration blocked behind it. It also gets *easier* later: every component reads through a hook, so
  unifying the stores changes five small hook files and nothing else.

- **Rigs, world geometry, meshes.** Stay Studio-authored, need reads only. A generated digest — a
  compact `Name :: ClassName [whitelisted props]` tree emitted into `docs/` — is the right answer
  and is a much smaller job. Not blocking.
- **`rojo syncback`.** Rejected for now. Its value is agent writes to non-UI assets, exactly the
  category being deferred, while its costs (binary blobs, merge conflicts, verbose diffs) land on
  the category being migrated away from.
- **Moving state ownership into React.** Explicitly out of scope (R4). Revisit only if the stores
  themselves become the problem.

## Status

**Phase R0: complete except the `actions/` scaffold**, which is deferred to R1 where the first real
commands appear. Builds clean; nothing is mounted yet, so none of it has run.

**Phase R1: complete and verified in Studio.** `ItemInspectPanel` renders, shows and hides correctly,
and its actions work. `ItemInspectRuntime` (596 lines) and `ItemInspectPanelPlugin` are deleted; the
Studio tree still needs removing by hand.

**Primitives pass: complete, one panel deep.** `PanelShell`, `Header`, `Slot`, `Grid`, `Tabs`,
`Gauge`, `Icon` are written and grounded in the exports rather than invented, and `ItemCard` was
refactored onto `PanelShell`/`Header`/`Icon` to prove them. `Slot`, `Grid`, `Tabs` and `Gauge` have
**not** been rendered yet — the first panel to use each one is also its first test.

This pass exists because the primitives are the contention point: every panel imports
`components/` and `themes/`, and `StyleRole` is a closed union with a startup assert, so parallel
agents adding roles independently is a guaranteed conflict. Building them centrally first is what
makes R2 delegation safe.

**Converted so far:** `ItemInspectPanel`, `SystemPanel`, `StatusPreviewPanel`, `EquipmentPanel`,
`InventoryPanel`, `SkillSlotContainer`. Every menu panel is React-driven and the plugin layer has no
plugins left — `PanelPluginRegistry`, `PanelPluginTypes`, `InventoryPanelPlugin`,
`EquipmentPanelPlugin`, `InventoryMenuRuntime`, `EquipmentMenuRuntime`, `EquipmentPanelRuntime`,
`SlotVisuals`, `PanelBinder`, `PanelTemplateResolver` and `SkillSlotUI` are all inert and awaiting a
deletion sweep once the last conversions are verified.

`SkillSlotContainer` is the first `ScreenRegistry` entry, so the screen-space path
(`ScreenRoot`/`HudRoot`/`ScreenRuntime`) is now exercised.

**Remaining:** `WorldLootInspectPanel` — the only unconverted panel, and the first user of
`PanelEntry.watch`, which has still never run.

**Deliberately staying imperative:** `OverheadHPBar` and `DamageLabel`. Both are per-entity/per-hit
`BillboardGui`s, a third mounting model that neither `PanelHost` nor `ScreenRegistry` covers, and
neither has layout worth reconciling. Damage numbers in particular are spawned per event and pooled,
where pooling matters more than declarative rendering. Note `ScreenGui` always composites above
`BillboardGui` in Roblox, so keeping them diegetic is what guarantees they cannot cover the HUD —
moving them to screen space would create that problem, not solve it. If the HP bar is ever moved to
React, use one root plus `createPortal` per bar rather than a root each (inverting R9's conclusion,
which was reasoned for a handful of panels rather than dozens of uniform bars), keep the
`BillboardGui` imperative and pooled, and drive the fill from a binding.

**Open, designed but not implemented:** see `docs/tasks/charging-as-casting.md`.

**Phase R2: `SystemPanel` and `StatusPreviewPanel` complete and verified in Studio.** Both were
delegated. `SystemPanel` needed a full rebuild after the first attempt — not the agent's fault, see
the `PanelShell` note below. `StatusPreviewPanel` landed close to right first time, on a corrected
doc.

`StatusPreviewController`, its three bar controllers, `SystemPanelRuntime` and
`StatusPreviewPanelPlugin` are all inert but still on disk, pending the deletion sweep.
`MenuMotionBridge` now owns the menu camera, which used to live in `SystemPanelRuntime`; it was never
panel-specific, keying off `modal.open` and the rig's focus point.

**`PanelShell` originally hardcoded a vertical stack**, and the handoff guide said to start every
menu panel with it — after comparing exactly two panels. `SystemPanel` is a composed layout of
absolutely positioned blocks inside an inset card, so following that instruction collapsed it into a
column. It now takes `inset` and `layout: "stack" | "free"`. **Check a panel's shape in the export
before assuming the stack fits.**

Three panel-level compositions have earned their way into `components/`: `RadialGauge` (the
two-half-mask ring), `VitalGauge` (icon/caption/bar/readout), and `PanelShell`'s two modes. Promote
on the second use, not the first — but do promote, because both panels had independently grown the
same icon-alignment bug in their private copies.

**Foundation pass (R2): complete, unverified.** The original `PanelHost`/`PanelRegistry` supported
exactly one shape — a menu-rig-placed panel whose visibility is a function of menu state — which
turned out to fit only `SystemPanel`, `InventoryPanel` and `EquipmentPanel`. Everything else was
blocked. Three changes opened it up:

- **Placement moved onto the entry.** `PanelHost` no longer reads `UIMenuConfig` and has no opinion
  about where a panel lives; `menuRigPlacement(id)` reproduces the old behaviour. This unblocks
  character-anchored and world-anchored panels.
- **`watch` added to `PanelEntry`.** Visibility can now depend on a non-menu source, re-evaluating
  just that entry when it fires. This unblocks panels driven by world state.
- **Screen-space layer wired.** `ScreenRegistry` + `HudRoot` + `ScreenRuntime`, started from
  `Bootstrap` alongside `UIRuntime`. `ScreenRoot` existed since R0 but was never started.

Unblocked by this: `StatusPreviewPanel`, `WorldLootInspectPanel`, `SkillSlotContainer`,
`OverheadHPBar`, `DamageLabel`. None of the new paths has run yet — the first panel to use each is
also its first test.

Also found during R2 planning: `QuestPanelPlugin` and `QuickActivationPanelPlugin` are empty stubs
with no runtime, no Studio tree and no export, and `NotificationPanelPlugin` maintains a queue
nothing reads. These are features to build, not panels to migrate, and should be dropped from the
migration scope.

Four bugs found in R1 that are now traps in this doc, all of which a converted panel could hit:

- A faded-out panel still absorbs pointer input (`GroupTransparency` does not gate hit-testing).
- Stacked `AutomaticSize` / `AutomaticCanvasSize` / `UIFlexItem` produces silent layout drift.
- A render throw could permanently strand a host's visibility (`UIRuntime` now pcalls).
- Porting `Design.rbxmx` tokens alone loses the design — the per-panel styling is on the instances.
  `tools/dump-rbxmx.ps1` exists to read it and should be run before converting anything.

Two integration details worth remembering, both found by reading before writing:

- `WorldGUIManager:setPanelVisibility` fades by tweening `BackgroundTransparency`/`TextTransparency`
  on every GuiObject descendant and caching originals as attributes. React owns those properties and
  would rewrite them mid-tween. `PanelHost` therefore mounts React inside a `CanvasGroup` it owns and
  fades `GroupTransparency` instead — one property, one owner.
- `MenuOrchestrator` exposes `onChanged`, not `subscribe`.

A fifth subscription shape turned up while writing `useAttributes`: `AttributesClient.onChanged`
returns a connection object with `:Disconnect()`, not an unsubscribe function. That is four distinct
shapes across five stores, which is the strongest argument yet for both the per-store hooks (R4) and
the deferred store unification.

The tooltip/carry interaction model (R14) is recorded but waits until every panel is ported and a
pointer-input spike proves it viable (R15).

Plan agreed 2026-07-30. React-lua chosen over a custom tree builder because the builder addressed
legibility only, and interactivity is the stated goal.

Open questions from the first draft resolved 2026-07-30: `StatusPreviewPanel` becomes a role rather
than a palette (R7), themes are parameterised (R8), all UI is code-mounted (R9), and the runtime
layer is redesigned rather than transcribed (R10).
