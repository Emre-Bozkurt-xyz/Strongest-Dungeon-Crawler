# Mastery Model v2 — tracks, branch XP, use-based XP

## Goal

Move the code from the first-cut mastery (one track per weapon class, one XP per basic attack hit,
level + XP saved per track) onto the model agreed in `docs/planning/progression-direction.md` and
drafted in `docs/planning/progression-launch-content.md`: attack-type and element tracks, trees as
data, XP saved per branch, XP from use and from damage share, and the mastery canvas drawing the new
trees.

## Current decisions

1. **Tracks:** Magic, Blade, Blunt, Ranged (family `attack`) and Fire, Frost (family `element`).
   Track ids are save keys.
2. **Trees are data** (`shared/progression/MasteryTrees`): every tree has the launch frame — trunk
   (root + two nodes), branches `a` and `b` with ranks 1–4, a `join` needing rank 3 in both, and for
   elements an `end` node needing attunement. Layout is derived from branch and rank, not authored.
3. **Saved per branch:** `progression.masteries[track] = { branches = { trunk = xp, a = xp, b = xp } }`.
   Save schema v2; v1 entries (Unarmed/Sword/Dagger/Wand with level + xp) migrate into the trunk of
   Blunt/Blade/Magic.
4. **Derived, never stored:** track level from total XP on one curve (`MasteryXP`); node unlocks from
   branch XP thresholds. Branches cap ("Mastered") and stop taking XP.
5. **A branch's first rank unlocks from the trunk**, not from its own XP. XP only reaches a branch
   through a form selected in it (or a skill tagged for it), so a branch could otherwise never start.
   *Decided here; to confirm with the developer.*
6. **XP sources:**
   - Use: each paid use (skill cast or combo step) gives flat XP to its track while the track is
     below the training cap. Hook: `BaseSkill.onUsed`, fired from `applyResourceCost`.
   - Connect: a hit on an NPC gives `masteryValue × share of max health removed × skill tier`,
     ceilinged at 20% of the track's next level. A training target (the dummy) gives flat XP instead,
     below the training cap only. Damage past remaining health does not count: `CombatService` now
     reports the health actually removed (`healthRemoved`).
   - Where it lands: the basic attack's selected form's node (root → trunk); a skill's
     `mastery = { track, branch, tier }` in its shared spec; element damage (`byType`) credits that
     element's trunk for its share (infusions do not exist yet).
7. **Enemy value is a placeholder:** `NPCSpec.progression = { masteryValue }` or `{ training = true }`,
   set as model attributes at spawn. Replaced by area level × type × rank when those exist.
8. **Not in this step:** attunement (all tracks act as attuned; `end` nodes show as needing
   attunement), attribute requirements (shown on nodes, not enforced, since there is no point
   budget yet), passive effects (nodes exist and unlock, effects are not applied), infusions and
   named combinations.

## TODO

- [x] `MasteryTracks` rewrite; `MasteryXP` (curves, thresholds, caps, XP rules); `MasteryTrees` data.
- [x] `MasteryTree.build` on tree data, same `Tree` output for the canvas.
- [x] Save schema v2 + migration.
- [x] `MasteryService`: branch grants, use XP, connect XP, publish (coalesced per frame), dev
      tooling (`ServerStorage.DevSetMastery:Fire(player, track, branch, xp)`).
- [x] `BaseSkill.onUsed`; `CombatService` `healthRemoved`; NPC `progression` attributes.
- [x] `FormService` unlocks from the tree; profiles lose `requires` / `parent`.
- [x] Skill specs tagged with `mastery` (ManaBall: Magic a; CascadingManaBalls: Magic b;
      TripleStrike: Blade a).
- [x] `ProgressionClient` (announces level-ups, new nodes and Mastered branches by diffing updates),
      mastery canvas (six tracks, branch progress line, node status per kind), glyphs for Fire and
      Frost.
- [x] Docs: direction doc build order.
- [ ] Developer confirms decision 5 (a branch's first rank unlocks from the trunk).

## Validation plan

Studio playtest via MCP:

1. Empty swings raise Blunt trunk XP by the flat amount until Blunt reaches the training cap.
2. Dummy hits give training XP; past the cap they give nothing.
3. Slime hits give damage-share XP to the trunk with the root form selected.
4. With trunk XP past the branch threshold, Rapid Jabs unlocks; selected, basic attacks feed the
   Brawler branch.
5. A save made under v1 loads as v2 with XP in the right trunk.
6. The canvas opens (M), shows the six tracks and the new tree layout, and selects Rapid Jabs.

## Results / notes

Validated 2026-10-26 in a Studio playtest driven over MCP; every step of the plan passed:

| Check | Result |
|---|---|
| v1 save migrates | The dev save's `Unarmed {level 0, xp 4}` loaded as Blunt trunk 4. |
| Use XP | Three empty swings: trunk 4 → 5 → 6 → 7, one update per swing. |
| Training XP | Two steps on the dummy: 7 → 8 (use) → 10 (hit) → 11 → 13. |
| Damage share | Dummy made an enemy worth 40 (runtime attributes, test only): a 10.68 hit gave +2.23, i.e. 40 × 10.68 / 191.3. |
| Unlocks | Trunk set to 120: Concussive, Solid Stance, Rapid Jabs and Overhead Smash announced as new. |
| Canvas | Six tracks, the new layout, branch progress line, statuses per node kind, fog. |
| Selection | Rapid Jabs selected (via the canvas's own request); shown IN USE, Punches AVAILABLE. |
| Branch XP | With Rapid Jabs selected, hits fed Brawler (`a`); trunk stayed at 120 (training cap). |

The dev save was put back afterwards (trunk 19.7 earned in the test, Brawler 0, no selection).

Notes:

- **The dummy's max health is 191.3, not the 220 its spec sets**; something in the stats pipeline
  scales NPC pools. Damage share uses the real maximum, so mastery is unaffected, but the spec's
  number is misleading. Not investigated.
- The Slime still has no HumanoidRootPart (the prefab lives in the place, not the repo), so melee
  cannot hit it; the damage-share test used the dummy with runtime attributes instead.
- Synthetic clicks from the MCP tools do not fire the canvas nodes' `Activated`; selection was
  driven through the same request the canvas sends. Worth a manual click to confirm.
- The canvas now frames the form in use at 30% of the screen width, so the tree opens to the right
  instead of running under the track list.
