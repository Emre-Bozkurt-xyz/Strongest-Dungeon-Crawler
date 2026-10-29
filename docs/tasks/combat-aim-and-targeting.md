# Combat aim, targeting and the crosshair

Status: **built 2026-10-28, first pass.** Verified in Studio with the wand, the sword and Cascading
Mana Balls against the Dummy. Not verified: flick-to-switch and drag-to-release under a lock (the
Studio tools cannot produce mouse deltas while the cursor is locked), crit and kill markers, and the
refused-attack jolt.

## What was wrong

- **Every shot went low.** `AimResolver` built its ray with `ScreenPointToRay` from
  `GetMouseLocation`, which is already in viewport coordinates, so the top bar's inset was added
  twice: the aim sat 58 px under the screen centre, about 4°, or 1.5 studs low at 20 studs.
- **The screen centre was on the character's head.** The over-the-shoulder camera is 2 studs right
  of the character but aimed at a point straight ahead of it, so the view converged back onto it.
  `CameraConfig.baseline.lookShoulderShare` (1 by default) now shifts the aim point sideways with the
  camera, so the centre passes beside the character. At 0 it is the old framing.
- **Melee swings went where the character faced** (parallel to the camera), not where the player was
  looking.

## The pieces

- **Crosshair** (`client/ui/panels/Crosshair`): a dot and four ticks at the screen centre, shown only
  while aiming (over-the-shoulder camera, cursor captured). On it:
  - the ticks close and turn the danger colour while attacks are going to an enemy within the basic
    attack's reach (a shot's flight, or a swing's cone), and dim while it is out of reach;
  - brackets over the target in the world: faint for the soft target, solid accent for a lock;
  - hit markers from the server's own `HitEvent`s: a cross for a hit, heavier in the crit colour
    (theme `critical`) for a critical, larger in the danger colour for a kill. No colour by element;
  - combo pips under it while the basic attack's chain is running;
  - a ring filling while a held skill charges (`HeldSkill:chargeDuration`, via `CombatSignals`);
  - a short jolt in the danger colour when an attack is refused for want of resources.
- **TargetAssist** (`client/SkillsFramework/TargetAssist`):
  - *Soft target*, always on: the enemy whose body is nearest the crosshair, within 8% of the screen's
    height, in range (60 studs) and in sight. Attacks go to it; nothing else changes.
  - *Lock*, middle mouse or T: keeps one enemy. The camera leaves it alone within 24° of the view's
    centre and turns just enough to hold it at that edge when it leaves (`trackTarget` camera
    modifier). A sideways flick of 150 px within 0.12 s switches to the nearest enemy that way;
    dragging it past 62° releases it, as do death, 75 studs, or a second out of sight.
  - The character turns to the target only for the attack (`CharacterFacingController:faceToward`),
    so moving under a lock is still moving where the camera points.
- **Aim**: a shot is aimed at the target's centre when there is one (`AimResolver.getAimPoint`);
  the server already turned any aim point into a direction from the muzzle, so nothing changed there
  and nothing new is trusted from the client.

## Open

- **Bows** do not exist yet. `TargetAssist.CAMERA_HOLD` takes a weapon class to "tight", which keeps
  a locked target centred; whether arrows should then fly straight at it, or keep drop so a moving
  target can escape, is undecided.
- Tuning: every number above is a first guess, at the top of `TargetAssist`.
- Gamepad has no aim or lock binding yet.
