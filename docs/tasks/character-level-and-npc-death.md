# Character Level & NPC Death

## Goal

Give the character level stream (docs/planning/progression-direction.md, "Experience") its first
source: killing NPCs. That needs NPCs that can die, which they could not: at 0 health they kept
standing and acting.

## Current decisions

1. **NPC death** (`server/NPCService/NPCDeath`): at 0 health an NPC is marked `Dead` (hit queries
   skip it; its behaviour already stops on an empty pool), listeners hear of it after the killing
   hit has reached every hit listener, and after 1.2 s it fades over 0.6 s and is removed. Spawned
   with `respawnDelay`, it returns where it first appeared. `immortal = true` in an NPC spec (the
   training dummy) refills instead of dying.
2. **No loot on death** yet: enemy loot is not designed.
3. **Character XP** (`server/Progression/CharacterService`): total XP saved in `character.xp`
   (template default, so no save migration); level derived from `shared/progression/CharacterXP`
   (`30 * level^1.9` to the next level, max 100, placeholder). Each level gained grants
   `POINTS_PER_LEVEL` (3, placeholder) attribute points.
4. **Kill XP is shared by contribution**: each player gets the share of the NPC's health they
   removed (`healthRemoved` from CombatService). Only NPCs with an `XPValue` are tracked, so a
   training dummy accumulates nothing. NPC values are placeholders in their specs
   (`progression.xp`: Slime 12, Goblin 20) until area level, type and rank exist.
5. **One progression channel, several owners** (`server/Progression/ProgressionSync`): mastery
   registers `masteries` and `shapes`, character registers `character`; updates coalesce per frame
   and carry `events` (`masteryLevel`, `characterLevel` with the points granted) for the client to
   announce. Replaces MasteryService's own publishing.
6. STATUS shows the real level and XP into it; a "LEVEL UP · LV n · +p POINTS" notice on level-up.

## TODO

- [x] NPCDeath, spawner lifecycle attributes, dead NPCs excluded from hit queries.
- [x] CharacterXP curve, save field, CharacterService (contribution, grant, points).
- [x] ProgressionSync; MasteryService and FormService moved onto it.
- [x] Client: snapshot `characterXp`, level-up notice, STATUS level and XP.
- [x] Dev hooks: `ServerStorage.DevHit:Fire(player, "Slime", 50)` (a real hit through
      CombatService on the nearest living NPC of that name), `ServerStorage.DevGrantXP:Fire(player, n)`.
- [x] Fix: attribute full syncs were dropped by the client (see notes).

## Validation plan / results

Studio playtest over MCP, 2026-10-26 -- all passed:

| Check | Result |
|---|---|
| Kill | Slime (220 health) killed with dev hits; marked dead, removed 1.8 s later. |
| Respawn | Back 10 s after death at its spawn point. |
| Kill XP | 12 XP, the full value (sole contributor). |
| Level-up | +30 XP: `characterLevel` event (level 2, 3 points), "LEVEL UP · LV 2 · +3 POINTS" notice. |
| STATUS | Level 2, "12 / 112 XP"; after a rejoin, level 3 kept and points 1006 (1000 + 2 levels). |
| Points live | +242 XP: level 4, points 1009 without reopening the panel. |
| Immortal | Dummy took 500 damage, stayed (not dead). |

The dev save now sits at character level 4 with 9 extra attribute points from these tests.

## Notes

- **Attribute full syncs never reached the client after the first.** `AttributesManager.sendFullSync`
  re-sent the current version instead of the next, and the client drops anything not newer than what
  it has. Anything that changed points through `setAvailableAttributePoints` (level-ups now) showed
  stale numbers until a rejoin. Fixed by giving a full sync the next version.
- The equipment validator still warns "requirements.level is not enforced (no progression system
  exists yet)". A character level now exists; enforcing gear level requirements is a design call
  (the direction doc says gear requirements are soft).
- A level-difference penalty is agreed but needs enemy levels, which do not exist yet.
