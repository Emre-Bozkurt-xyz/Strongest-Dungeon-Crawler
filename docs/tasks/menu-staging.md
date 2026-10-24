# Menu Staging — panels placed for the character, camera placed to watch

Status: **second design, implemented 2026-10-24, awaiting playtest.** Verified in Studio at 16:9: all
three views, the camera settle, and the wall flip. Not yet verified: real pointer clicks on staged
panels, other aspect ratios, a camera walled in on both sides. Precedes the design pass
(`ui-design-pass.md`), because it decides how large a panel is on screen.

## The problem

The menu camera was the gameplay over-the-shoulder camera pushed out and aimed at a weighted average
of the panel positions. Measured with the inventory open at 1920x1080: camera 3.3 right, 2.65 up,
2.66 behind the HumanoidRootPart; panel 7.27 studs away, tilted 21° away from the camera, filling 39%
of the view width, with the character's head over its lower-left corner. Far, small, oblique, and
the wider the panel the worse.

## The model

**The panel and the camera are placed independently, and neither aims at the other.**

- **Panel** — where it would make sense for the character to read it: ahead of it, biased to one
  side, at about eye height, turned mostly toward the character's head (`faceCamera` blends toward
  the camera; yaw only, panels stay upright). Side panels (ItemInspect) continue the primary's plane
  outward.
- **Camera** — its own seat in the character's frame (`right`/`up`/`back`) with its own look
  direction (`yaw`/`pitch` from the character's facing). It does not look at the panel or at a
  midpoint; composition comes from tuning the two poses.
- **Scale** — menu panels are shrunk to character scale (`surface.scale = 0.72`). A 6.5-stud panel at
  arm's length dwarfs a 4-stud-wide R6 character. The part shrinks and `pixelsPerStud` grows
  inversely, so the canvas — and every pixel constant a panel derives from it — is unchanged.

Current seat for the reading views (system, inventory): camera behind the right shoulder at about
head height, looking down the character's line of sight; panel 3.7 ahead, 2.1 right, 1.8 up. The head
and shoulder take the lower-left of the frame and the panel sits centre-right, turned toward the
character. Equipment uses the same idea a little further out and higher, for the taller paper doll.
All values are in `UIMenuConfig.stage.views`.

Both poses come from the character's position and the yaw captured on open, so nothing reads a live,
smoothed position and there is no feedback loop (rule 3 of `menu-rig-runtime.md`).

### Walls

The side (authored, or mirrored to the character's left) is chosen on open and on view change, never
per frame. It mirrors when the ray from the head to the camera seat, or to the composition's outer
edge, is blocked. The outer edge counts the primary's half width plus every side panel that could
open on that side, so an inspect panel opened later does not land in the wall. When mirrored, the
camera, the panel bias and the side panels all flip. If both sides are blocked the camera is pulled
in along its ray.

### Camera move

`CameraController` takes a `poseProvider` modifier and travels to it in a fixed time eased to a hard
stop (`stage.cameraMove`, 0.32s, quart-out), then holds the pose exactly. A pose's `key` (the view)
changing restarts the move from wherever the camera is. Closing is a matching move back to the
gameplay pose (`stage.cameraRelease`, 0.22s). This replaced an exponential settle, whose long tail
read as floaty. `_yaw`/`_pitch` are untouched, so closing returns the gameplay camera to where it was.

In Free mode the return blends after Roblox's camera computes each frame, and puts Roblox's own pose
back before its next update: Roblox reads `camera.CFrame` back as state, so leaving the blended frame
in place pulled its zoom in and it snapped out (6.5 studs in one frame) when the blend ended.

**Both camera modes.** Over-shoulder runs the controller's own loop, which checks for a staged pose
first. Free mode (V) hands the camera to Roblox's controller and runs no loop of ours, so originally
the panels were staged but the camera never moved — the shot depended on wherever the free camera
was. `_syncStagedLoop` now takes the camera back as Scriptable with its own render step whenever a
pose provider is active in free mode, and returns it (CameraType `Custom`, FOV restored) when the
pose goes away. Pushing or popping a modifier and switching modes all re-sync. Switching modes with
the menu open works, but entering over-shoulder turns the character to the camera's yaw.

## History

The first version (commit `84879c6`) inverted the problem the other way: camera beside the character
with the character out of frame, panels square to the camera and fitted to fill a share of the view.
It was readable, but it flattened the panels onto the camera — "might as well have made it HUD space
GUI" — and lost the character entirely. Two lessons from it survive:

- **Wide FOV stretches off-centre panels.** At 65° vertical on 16:9 the horizontal FOV is ~97°, and
  anything off-centre reads as tilted. The menu renders at 55°.
- **`SurfaceGui.AlwaysOnTop` does not render the `CanvasGroup` PanelHost fades** — the panel vanishes.
  So panels can still intersect geometry the wall check does not catch (anything not on the ray
  from the head to the outer edge).

## Hazards still open

- **Geometry between the head and the panel's lower half** — the wall check is a single ray per side.
- **Pointer input** — synthetic MCP mouse clicks do not reach world-space SurfaceGuis (a ray from the
  reported mouse position hits the panel and the SurfaceGui is Active, but nothing registers), so
  click behaviour on staged panels has to be checked by hand.
- **Other aspect ratios** — composition is authored at 16:9; a narrow screen crops the panel's right.

## Iterating on this

Composition is taste, so tune it by eye with the **stage tuner**: press F6 in a Studio playtest
(`src/client/ui/dev/StageTuner.luau`, registered in `ScreenRegistry` only under `RunService:IsStudio()`).

- Per view: camera `right/up/back/yaw/pitch/fov` and panel `ahead/right/up/faceCamera/turn/tilt`.
  The view tabs also open the menu on that view. Globals: panel scale (applied live through
  `UIRuntime.setPanelScale`), spacing, settle rate.
- Each value has a slider, ±step buttons, and a box that takes any typed number, including beyond the
  slider's range.
- Values are DevTuningService overrides under `UIMenu.stage`; `MenuRigRuntime` re-reads them every
  frame and the camera takes FOV and settle rate from the pose provider, so everything is live.
- **Export** prints a `stage = { ... }` block (and shows it in a selectable box) to paste over
  `UIMenuConfig.stage`. Nothing persists until it is pasted. **Copy to all views** copies the
  edited view's poses to the others; the dock button moves the overlay to the other screen edge.

For changes the tuner cannot express, a probe during a playtest still works: clone the panel part,
place it with the same maths as `MenuRigRuntime._solve`, and pin the camera.

**`screen_capture` with `camera_position` does not place the camera reliably during a playtest.**
Pin the real camera from the Client datamodel instead and capture without camera arguments:

```luau
RunService:BindToRenderStep("StageCamProbe", Enum.RenderPriority.Last.Value, function()
    workspace.CurrentCamera.CFrame = camCF
    workspace.CurrentCamera.FieldOfView = 55
end)
```

`Last` runs after `CameraController`, so this wins every frame. Stopping the playtest clears it.

`execute_luau` runs in its own module cache: requiring a game module there gives a fresh,
uninitialised copy, and initialising one (e.g. `InventoryService` server-side) starts a duplicate stack
that spams the log. Probe with instances, not module state.

