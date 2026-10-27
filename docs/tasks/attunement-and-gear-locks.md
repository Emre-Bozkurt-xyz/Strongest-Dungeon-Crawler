# Attunement, Gear Locks & Slime Prefab

## Goal

Three things asked for on 2026-10-27:

1. Gear whose requirements are not met cannot be equipped, so trading cannot break progression.
2. Attunement, changed at a placeholder shrine that costs nothing (there is no currency yet).
3. Fix the Slime prefab.

Loot, NPC logic and NPC visuals are left for a separate pass.

## Current decisions

1. **Gear requirements are hard** (`server/Inventory/Projection/RequirementEvaluator`):
   - **Level and attributes are both enforced.** Attributes already were; level now is, read from
     the save so the inventory does not require CharacterService (that would pull combat and NPC
     modules into a require cycle).
   - **Equipped gear that stops qualifying is suppressed** (`active = false` in the projection). It
     gives no stats, and the combat loadout treats a suppressed weapon as absent, so the character
     fights unarmed. Before this change a suppressed weapon still dealt full damage.
   - **Attributes from other gear count, never an item's own.** `resolveActive` activates items in
     passes, each pass counting only items already active. Equip validation runs the same
     resolution on the equipment as it would be after the equip, so validation and projection
     cannot disagree. Before, the projection ignored gear attributes altogether.
   - **The projection recomputes** after a level-up and when base attributes change (points spent,
     a reset), coalesced per frame.
   - **The client shows it:**
     - the inspect card's Level row shows your level and whether it's met;
     - Equip is disabled while any requirement is unmet;
     - inactive equipped gear reads "Status: Inactive";
     - a refused equip (for example a click on the Equipment panel) shows "CANNOT EQUIP · LEVEL TOO
       LOW" or "NOT ENOUGH STRENGTH".
2. **Attunement** (`shared/progression/Attunement`, `server/Progression/AttunementService`):
   - **Slots come with character level:** one at level 3, two at level 6. Both are placeholders
     inside the agreed 5–10 window for the second.
   - **The saved list is cut to the slots the level allows**, so retuning slot levels needs no
     migration.
   - **Attack-type tracks need it.** Earned nodes of an unattuned attack track are *dormant*: shown,
     but not selectable. A selected form that goes dormant falls back to the weapon's default, and
     the selection is kept. Root forms always work.
   - **Element tracks always work.** Attuning one opens its end node.
   - **XP is earned either way.**
3. **Shrines:**
   - **A shrine is any instance in the world tagged `AttunementShrine`.** The server gives each one
     a prompt.
   - **The prompt opens the mastery canvas in shrine mode.** Under the track list, a panel shows
     slots used and an ATTUNE / RELEASE button for the shown track. Shrine mode ends when the player
     walks out of range.
   - **Away from a shrine, the canvas header** says what is attuned and where to change it. Attuned
     tracks carry a diamond in the track list.
   - **Every change is a `ProgressionAttune` request**, checked on the server: within 14 studs of a
     shrine, a free slot, and a minimum interval between requests.
   - **Changing attunement is free.**
   - **Dev placeholder:** InitDev builds a shrine (slab, pillar, floating crystal) at (80, ground,
     −14), next to the dev Dummy and Slime.
4. **Notices:**
   - "ATTUNED" / "RELEASED" when a track changes;
   - "NEW ATTUNEMENT SLOT" on the level-up that opens one;
   - "CANNOT ATTUNE · NO FREE SLOT" or "TOO FAR FROM THE SHRINE" when a change is refused.
5. **Slime prefab** (`ReplicatedStorage.Assets.NPCPrefabs.Slime`, in the place file, not in Rojo):
   - Root part renamed `RootPart` → `HumanoidRootPart`, which movement, combat and behaviour all look
     up.
   - Humanoid set to R15 with HipHeight 0.168, so it stands on the floor. As R6 with no legs, it
     could not stand.
   - Skin meshes made non-colliding and massless.
   - The AnimationController removed, so the Humanoid's Animator is the only one (it is what
     NPCAnimationController uses).
   - **`EvaluateStateMachine` turned on.** It was off, which left the Slime frozen in its first
     state. This was the real cause of the "slime doesn't move" issue.

## Validation results

Studio playtest over MCP, 2026-10-27. The client was not rendering, because the Studio window was in
the background: screenshots timed out and proximity prompts never showed. So the prompt → canvas
path and the canvas visuals are **not verified**. Everything else was checked through real network
requests:

| Check | Result |
|---|---|
| Level lock | Iron Dagger, temporarily set to level 5: refused at level 4 (`requirement_failed::Level`), and at 796 XP (still level 4); equipped at level 5. |
| Attribute lock | Leather Chest: refused (`requirement_failed::Dexterity`). |
| Normal equip | Iron Sword equips. |
| Attune away from shrine | Refused (`not_at_shrine`). |
| Slots | Level 5: Blunt attuned; Fire refused (`no_free_slot`). |
| Dormant | Rapid Jabs selectable with Blunt attuned; after release, refused (`locked`) and the selection is kept. Unarmed loadout shape: nil while released (default), `unarmed_rapid_jabs` once re-attuned. |
| Slime | Spawns standing at hip height and patrols; it attacked the player when near. |

The dev save ends at character level 5 with Blunt attuned, Blunt trunk at 150 XP, and Rapid Jabs
selected for unarmed.

## Notes

- **To check in Studio:**
  - walk up to the shrine, press E, and look at the canvas shrine panel;
  - inspect a locked item;
  - drag-equip one to see the notice.
- **Save the place.** The Slime prefab fix lives only in the open place.
- **NPCs are physics-owned by the nearest player's client** (automatic network ownership). With the
  state machine off, the Slime stayed frozen even after a server-side state change, until the server
  took ownership. Server-owned NPC physics is worth considering in the NPC pass.
- **Untested path:** suppression of already-equipped gear (no way yet to lower attributes in play).
  It uses the same `resolveActive` as equip validation, which was tested.
