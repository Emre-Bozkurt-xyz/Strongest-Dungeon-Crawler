## World-Space Item Inspect

### Problem
The old loot inspect path reused the modal `ItemInspectPanel` runtime.

That is the wrong class for world-space loot because:
- it follows the player
- it uses menu-oriented placement assumptions
- it assumes one inspect surface instead of a localized loot context

Result:
- the inspect panel appears in front of the player instead of near the loot
- the behavior does not scale to multiple nearby drops

### Direction
Create a separate world-space inspect panel class instead of stretching the modal inspect panel further.

Recommended split:
- `ModalItemInspectPanel`
  - used by inventory/equipment/menu side inspect
  - owned by `MenuOrchestrator` / `MenuRigRuntime`
- `WorldLootInspectPanel`
  - used for nearby drops in the world
  - owned by a dedicated loot/world-panel runtime

### Design Rules
1. World loot inspect should anchor to loot context, not to player-follow menu placement.
2. It should support more than one drop without producing overlapping unreadable panels.
3. It should remain compact and glanceable, not a full inventory-style inspect card.
4. It should support direct actions such as pickup without requiring modal menu state.

### Likely Runtime Shape
- `LootInspectRuntime`
  - discovers nearby eligible drops
  - groups drops by proximity cluster
  - chooses one compact panel per cluster
- `LootInspectPanelRuntime`
  - renders a compact vertically stacked list
  - supports scrolling when cluster size exceeds visible capacity
- `LootInspectController`
  - handles prompt/keybind/pickup intent

### Grouping Approach
For overlapping or dense loot fields:
- cluster drops by proximity
- render one compact panel for the cluster
- sort entries by:
  - distance
  - rarity
  - recency

That avoids one panel per item when many drops occupy roughly the same space.

### First Implementation Pass
1. keep current modal inspect untouched
2. add dedicated world-loot inspect runtime and template
3. anchor panel to loot cluster centroid or lead item
4. show compact list with pickup action
5. only revisit richer item detail after the clustered panel is stable

## Implementation Todo

### Phase 1: Server Hardening
- [x] Stop trusting client-supplied drop positions.
- [x] Compute drop spawn position on the server from player/world context.
- [x] Validate pickup distance on the server before granting the item.
- [x] Add initial claim-window semantics instead of permanent owner-only behavior.
- [x] Add compact replicated loot display attrs:
  - `ItemDisplayName`
  - `ItemRarity`
  - `ItemStackSize`

### Phase 2: Client Runtime Split
- [x] Remove world-loot inspect from the modal inspect/menu path.
- [x] Add `WorldLootInspectRuntime`.
- [x] Rewrite `LootClient` to manage active nearby loot entries instead of calling `MenuOrchestrator.setInspect("external", ...)`.
- [x] Hide world-loot inspect while the modal menu is open.

### Phase 3: Interaction Model
- [x] Default selected row = top/nearest row.
- [x] `E` picks the currently selected row.
- [x] Hover/select + `PickupButton` supports precise row interaction during `Precision Focus`.
- [x] Keep stock ProximityPrompt UI disabled; use custom panel as the visible interaction surface.
- [ ] Add a final explicit clustered-loot interaction model for dense multi-drop scenarios.

### Phase 4: Cleanup
- [x] Remove old `external` loot-inspect coupling from the modal inspect path.
- [ ] Re-test dense drop scenarios.
- [ ] Decide whether to move from one active panel to clustered multi-panel loot groups later.

## Editor Template Contract

### Template Path
Create this asset path:

`ReplicatedStorage/Assets/WorldUI/PanelTemplates/WorldLootInspectPanel`

Follow the same pattern as the other panel templates:
- a container under `PanelTemplates`
- child `WorldPart`
- child `SurfaceGui`
- content rooted under a `Root` frame inside your normal background shell

### Expected Hierarchy

Recommended structure:

```text
WorldLootInspectPanel
  WorldPart (BasePart)
    SurfaceGui
      Background (Frame)
        Root (Frame)
          Header (Frame)
            TitleLabel (TextLabel)
          LootContainer (ScrollingFrame)
            UIListLayout
            RowTemplate (Frame)
              SelectionFrame (Frame or ImageLabel) [optional but recommended]
              RarityFrame (Frame or ImageLabel) [optional but recommended]
              Content (Frame) [optional]
                Icon (ImageLabel)
                NameLabel (TextLabel)
                StackLabel (TextLabel) [optional]
              PickupButton (TextButton)
          Footer (Frame) [optional]
            HintLabel (TextLabel) [optional]
```

### Required Names I Plan To Bind

Required:
- `WorldPart`
- `SurfaceGui`
- `Root`
- `LootContainer`
- `RowTemplate`
- `Icon`
- `NameLabel`

Strongly recommended:
- `SelectionFrame`
- `RarityFrame`
- `StackLabel`
- `HintLabel`

### Binding Notes
- `RowTemplate` should start `Visible = false`, same as the other template-driven panels.
- `LootContainer` should be a `ScrollingFrame`.
- `RowTemplate` should be a plain `Frame`, not a `TextButton`.
- `PickupButton` is the explicit immediate-action surface for mouse pickup.
- `SelectionFrame` is where I’ll drive the active-row highlight.
- `RarityFrame` is where I’ll drive the rarity tint / future frame image treatment.
- The runtime will search recursively by name, so `Background > Root > ...` is fine and matches the current panel style.

### Styling Guidance
- Keep it more compact than `ItemInspectPanel`.
- Think “loot strip / nearby list”, not “full detail card”.
- Rows should support 3-8 visible items comfortably before scrolling.
- Leave room for a persistent footer hint like:
  - `E Pick Up`
  - `Hold LeftAlt to interact with rows`

### Optional Nice-To-Haves
- `EmptyLabel` for “No loot nearby” if you want an editor-authored empty state
- `PromptKeyLabel` if you want the key hint isolated from the footer body
- `SubtitleLabel` if you want to show cluster context later
