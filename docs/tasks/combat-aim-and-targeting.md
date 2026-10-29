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

- **Crosshair** (`client/ui/panels/Crosshair`): a dot and four short rounded strokes at the screen
  centre, shown only while aiming (over-the-shoulder camera, cursor captured). Minimal on purpose,
  in one pale ink that runs from a cool to a warm white (the user asked for a white with some
  texture, not plain white), with a soft dark edge so it reads over sky. On it:
  - the strokes close in while attacks are going to an enemy within the basic attack's reach (a
    shot's flight, or a swing's cone), and dim while it is out of reach. No colour change;
  - corners over the target in the world: short and faint for the soft target, longer and full for
    a lock, closing in on the enemy as it is locked. Always a square, sized to the enemy: its
    model's larger side plus 15%, measured once when it is first marked (bounds move with every
    animation frame). An enemy whose model measures badly sets a `TargetFrame` number attribute
    (the side in studs) on its model; nothing else needs authoring per enemy;
  - hit markers from the server's own `HitEvent`s: a cross for a hit, longer and pale gold (theme
    `critical`) for a critical, longest and pale red for a kill. No colour by element;
  - combo dashes under it, lit up to the step just played. After the last step they empty over its
    end lag and stay empty a moment, so the chain is seen to reset before the next one starts;
  - a tall thin arc to its right while a held skill charges (`HeldSkill:chargeDuration`, via
    `CombatSignals`): a line filling bottom-up in the ink for a smooth charge (a bow's draw, later),
    or, when the skill counts its charge in whole things (`HeldSkill:chargeShape`), beads on the
    arc that start empty and fill in the resource's colour -- Cascading Mana Balls draws six beads,
    five balls each, filling light blue;
  - a short shake and a red flash when an attack is refused for want of resources.
  - Under a lock the target's corners become the crosshair: the dot and strokes fade, the corners
    dim and flash as the strokes did, and the hit markers, combo dashes (below the corners) and
    charge arc (right of them) glide onto the target in 0.18 s, and back when the lock ends.
- **TargetAssist** (`client/SkillsFramework/TargetAssist`):
  - *Soft target*, always on: the enemy whose body is nearest the crosshair, within 8% of the screen's
    height, in range (60 studs) and in sight. Attacks go to it; nothing else changes.
  - *Lock*, middle mouse or T: keeps one enemy. The camera leaves it alone within 12° of the view's
    centre (24° at first; the user found that too loose) and turns just enough to hold it at that edge when it leaves (`trackTarget` camera
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
