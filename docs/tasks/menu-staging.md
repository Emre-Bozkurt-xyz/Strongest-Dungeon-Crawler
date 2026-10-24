# Menu Staging — camera beside the character, panels fitted to the view

Status: **implemented 2026-10-24, awaiting playtest.** Verified in Studio at 16:9: all three views,
close, and the wall flip. Not yet verified: real pointer clicks on staged panels, other aspect
ratios, a camera walled in on both sides. Precedes the design pass (`ui-design-pass.md`), because it
decides how large a panel is on screen, and every type size and density decision downstream depends
on that.

## As built

- `MenuRigRuntime` is the stage: one `_solve()` returns the camera CFrame and a CFrame per panel.
  Basis yaw is captured on open; the side (right, or mirrored left) is chosen on open and on view
  change by raycasting from the shoulder, never per frame, so walking along a wall cannot flip it.
  When mirrored, side panels and `shift` mirror too.
- Reserved slots: `reserve` keeps ItemInspect's slot open in inventory and equipment, so the primary
  does not jump when an item is inspected. Panel sizes are declared to the rig by `UIRuntime` from
  the registry, because a side panel's part does not exist until first shown.
- `CameraController` gained a `poseProvider` modifier field; `MenuMotionBridge` pushes it with the
  stage's FOV. `_yaw`/`_pitch` are untouched, so closing returns the gameplay camera to exactly where
  it was. The glide is the existing per-frame lerp at 0.16 (D3 is still open).
- `WorldGUIManager` accepts a CFrame from an override provider, keeps providers by name so one set
  before its panel registers still attaches, and exposes `snapPanel`. `PanelHost` snaps every panel
  on show.
- Config is `UIMenuConfig.stage` (per-view pose, fill, shift, reserve). The old player-space offsets,
  arc layout and centre weights are gone.

### Found while building

- **The menu FOV is 45, not 65.** At 65 the horizontal FOV on 16:9 is ~97°; a panel pushed
  off-centre by a reserved slot is visibly stretched by the wide-angle projection and reads as
  tilted even when it faces the camera exactly. 45 is flatter and more screen-like.
- **`SurfaceGui.AlwaysOnTop` does not render the `CanvasGroup` PanelHost fades** — the panel vanishes
  entirely. So the "panels clipping into walls" hazard below is unsolved; the side flip covers the
  common corridor case, but a panel can still intersect geometry ahead of the camera.
- **Synthetic MCP mouse clicks do not reach world-space SurfaceGuis.** A ray from the reported mouse
  position hits the panel and the SurfaceGui is Active, but neither hover nor click registers. Pointer
  behaviour on staged panels has to be checked by hand.
- **Equipment framing** puts the camera ~9 studs out at the character's front-right
  (`right = 5.2, back = -7.4, turn = 122`), which sits the character ~23° left of the axis with the
  paper doll beside it at the same depth. The character reads larger than computed; tune by eye.

## The problem

The menu camera is the gameplay over-the-shoulder camera, pushed further out
(`CameraConfig.modifiers.systemMenuFocus`), looking at a weighted average of the panel positions.
Measured 2026-10-24 with the inventory open at 1920x1080:

| | |
| --- | --- |
| Camera, relative to HumanoidRootPart | 3.3 right, 2.65 up, 2.66 behind |
| Inventory panel, relative to HRP | 0.3 right, 1.2 up, 3.8 ahead |
| Camera to panel | 7.27 studs |
| Panel width as a share of the view | **39%** |
| Panel tilt away from the camera | **21°** |

The panel is far, small and oblique, and the character's head and shoulder cover its lower-left
corner. Wider panels suffer most: inventory is 6.5 studs across, so at that distance its text is
tiny, and the tilt makes the far side smaller still.

The root cause is that the camera is placed for gameplay and then aimed at the panels. The panels
never get a say in where the camera is.

## The idea

Invert it. **The menu has its own camera pose, and the panels are placed to fit that pose.**

1. **Camera pose** — beside the character at a little under shoulder height, like a slightly
   shorter person standing next to them, facing the way the character faces. Derived from the
   entry basis (character yaw at menu open), which `MenuMotionBridge` already captures.
2. **Panel placement** — in camera space, square to the camera, at whatever distance makes the
   composition fill a target fraction of the view. Distance is solved from the FOV, the viewport
   aspect and the composition's width — not authored as studs.

Both come from the same basis, so this keeps rule 3 of `menu-rig-runtime.md` (the camera never
derives framing from live, smoothed panel positions). It removes the loop entirely: neither reads the
other.

### Fit-to-view

```
hfov     = 2 * atan(tan(vfov / 2) * aspect)
distance = (compositionWidth / fill) / (2 * tan(hfov / 2))
```

Also check height (`compositionHeight / fill` against `vfov`) and take the larger distance, so a tall
panel (EquipmentPanel, 6.2 studs) fits vertically too. Recompute on `ViewportSize` change.

This is the part that makes readability *guaranteed* rather than tuned: a wider screen pulls panels
in, a narrower one pushes them out, and the same panel always occupies the same share of the frame.

## Prototype (2026-10-24, in Studio)

Done by hand during a playtest: a clone of InventoryPanel placed by the formula above, with the
camera pinned by a render step (see "Iterating on this" below for why).

| Variant | Pose (right, up, back from HRP) | Result |
| --- | --- | --- |
| A | 2.4, 0.9, 1.6 | readable, but the head covers the panel's left third |
| B | 2.7, 0.75, 0.6 | the arm fills the left of the frame |
| C | 3.4, 0.55, 2.2, yawed 12° in | the character is in frame and overlaps the panel |
| D | 2.6, 0.55, 0.9 | still the arm |
| **E** | **3.2, 0.7, 0.0** | **clean: panel at 3.97 studs, 72% of view width, square, every label legible** |

The character is an R6 rig, 4.0 studs wide including arms and 1.0 deep, with shoulders about 1.0
above the HRP. Any pose that keeps the character in frame and the panel large ends up overlapping
them; there is not room for both at this panel size. Variant E clears the character because the
nearest arm edge is about 69° off the camera axis, well outside the 48.5° half-FOV at 16:9.

## Decisions

**D1 is decided: per-view poses (c)**, revisited after playtesting. D2 and D3 are open.

**D1. Is the character in frame?** E removes it, which is what makes the panel readable. The cost
is diegetic weight — the menu stops feeling like it lives beside the character. Options:

- **(a) Out of frame (E).** Maximum readability. The world still shows behind the translucent panel.
- **(b) Shoulder peeking at the left edge.** Camera ~3.0 right, ~0.3 behind; the panel shifts right
  by ~10% of its width. Some presence, some lost width.
- **(c) Per-view poses.** Inventory and System use (a). **Equipment turns to face the character** —
  the camera swings to the front-right and the paper doll sits beside the actual character, which is
  the one view where seeing the character is the point. Recommended: it spends the diegetic budget
  where it pays.

**D2. Fill target.** 0.72 read well for one panel. A primary plus ItemInspect side-by-side should fit
as a group at roughly 0.85, the inspect card angled slightly toward the camera (the rig's existing
arc layout gives this).

**D3. Transition.** The camera has to travel from the gameplay pose to the menu pose. A short eased
move (~0.25-0.35s) with the panels materialising during it reads as "turning to look at the
System". This is the first motion the design pass will want to own, so build it on whatever motion
primitive that pass settles on rather than a one-off tween.

## Hazards

- **Walls.** A camera 3.2 studs to the character's right is inside the wall in any corridor.
  Raycast from the character's shoulder to the camera pose; if blocked, mirror to the left side, and
  only pull in if both sides are blocked. Dungeons make this the common case, not an edge case.
- **Panels clipping into geometry.** Panels 4 studs ahead will intersect walls just as often.
  `SurfaceGui.AlwaysOnTop = true` renders them over geometry and makes this disappear; check it does
  not break the translucent look (it also removes depth sorting between panels, which the arc layout
  does not rely on).
- **Pointer input.** Square, near panels are the best case for R5's pointer spike — fold the spike
  into this work rather than running it against the old oblique layout.
- **Gameplay camera hand-off.** On close, restore the gameplay yaw the player had, not the menu yaw.

## What changes

- `CameraConfig.modifiers.systemMenuFocus` — new pose fields (right/up/back relative to the basis),
  per-view if D1(c). `lookAtProvider` goes: the camera looks along the basis, not at the panels.
- `MenuRigRuntime` — the slot solver keeps its buckets and spacing but solves in **camera** space
  from the menu pose, and adds the fit-to-view distance. `getFocusPoint` loses its only consumer.
  This deliberately breaks the migration plan's "never touch MenuRigRuntime" rule; that rule existed
  to keep the React port a port.
- `UIMenuConfig.panels[*].playerSpaceOffset` — replaced by the solver; per-panel tuning becomes
  layout role and order only.
- Panel `faceMode` — `"camera"` instead of `"playerYaw"`, so each panel faces the viewer.

`WorldGUIManager` needs nothing new: override providers and `faceMode = "camera"` already exist.

## Iterating on this

**`screen_capture` with `camera_position` does not place the camera reliably during a playtest** —
the captures came back skewed, with the character far closer than the requested pose allowed.
Instead, pin the real camera from the Client datamodel and capture without camera arguments:

```luau
RunService:BindToRenderStep("StageCamProbe", Enum.RenderPriority.Last.Value, function()
    workspace.CurrentCamera.CFrame = camCF
    workspace.CurrentCamera.FieldOfView = 65
end)
```

`Last` runs after `CameraController`, so this wins every frame. Stopping the playtest clears it.

Also: `execute_luau` runs in its own module cache, so requiring a game module there gives a fresh,
uninitialised copy — and initialising one (e.g. requiring `InventoryService` server-side) starts a
duplicate stack that spams the log. Probe with instances, not module state.

Check every view at 16:9, 21:9 and 4:3 before calling it done.
