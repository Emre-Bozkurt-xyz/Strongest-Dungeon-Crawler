# Infusions & Named Combinations

## Goal

Build step 4 of `docs/planning/progression-direction.md`: the basic attack's form becomes the
selected shape plus a selected infusion, under the generic rule, with named combinations on top.
Launch content is in `progression-launch-content.md`.

## Current decisions

All numbers are placeholders, to tune with combat.

1. **Infusion data lives on the tree nodes** (`MasteryTrees`, `infusion = { element, conversion,
   surcharge }`):

   | Tier | Converts | Cost surcharge |
   |---|---|---|
   | Fire I / Frost I | 25% | +10% |
   | Fire II / Frost II | 50% | +20% |
   | Fire III / Frost III | 100% | +30% |

   Fire III and Frost III are join nodes: they need rank 3 in both branches.
2. **The generic rule** (`shared/skills/BasicAttackForm`):
   - An infusion converts its share of every other damage type in a step to its element. Damage
     already of that element is left alone.
   - **Potency** scales the converted part: `1 + 1% × element level`, with the per-level part ×1.5
     when the element is attuned. This is the continuous growth inside a node, and what attuning
     an element strengthens.
3. **Cost:** an infusion adds its surcharge to the shape's cost, on the shape's own resource.
   Charging a second resource (stamina and a little mana) needs the cost pipeline to carry more than
   one resource; left for later.
4. **Selection:**
   - One infusion or none, for the character, carried over to any weapon. Saved as
     `progression.infusion`.
   - The request is `LoadoutSelectInfusion { infusionId }`, where `""` clears it.
   - The server checks the node is an unlocked infusion. Element tracks are always active, so no
     attunement is needed.
   - The selection reaches combat as `CombatLoadoutSnapshot.basicAttackInfusion = { id, potency }`.
   - The loadout is recomputed whenever a mastery level changes, since potency depends on the
     element's level (`MasteryService.onProgressChanged`, formerly `onUnlocksChanged`).
5. **Named combinations** (`shared/progression/FormCombinations`):
   - Keyed by shape node + infusion node.
   - All seven launch pairs are listed, so the canvas can advertise them.
   - Only **Fireball** (Mana Ball + Fire III) resolves today; the other six need shapes that have no
     profile yet.
   - Fireball:
     - +20% cost on top of the infusion's surcharge;
     - projectile 1.8× size;
     - impact effect 4× size;
     - on impact, every other enemy within 8 studs takes 60% of the step's damage.
6. **Mastery XP:**
   - An infused basic attack feeds its infusion's node in the element track: use XP and training XP,
     each below the training cap.
   - When it connects, the element's share of the earned XP goes through the infusion's node. A join
     infusion splits it between both branches.
   - Element damage from anything else still lands in the trunk.
7. **Looks** (`client/fx/ElementLook`):
   - Infused projectiles and their impacts are the weapon's own templates, recoloured to the
     element's track colour (`MasteryTracks.color`) and resized for a combination.
   - Pooled projectile visuals are keyed by look, so a recoloured clone never comes back plain.
   - A hit carrying element damage plays a recoloured burst on the target (`ElementHitFX`), so melee
     forms read as infused too.
   - Damage numbers use the element colour.
8. **Canvas:**
   - Infusion nodes are selected by clicking. Clicking the one in use clears it.
   - Nodes read "IN USE" or "AVAILABLE".
   - A node that would make a named combination with the other half of the current form shows it,
     e.g. "IN USE · FIREBALL".
   - The pairing comes from progression data through `MasteryTree.pairingFor`, the same rules the
     server applies, so it doesn't depend on which network update arrives first.
9. **Also done:**
   - `Frost` added as a damage type.
   - The canvas hint uses "/" instead of "·", which Michroma does not render.

## Validation results

Studio playtest over MCP, 2026-10-27:

| Check | Result |
|---|---|
| Select / clear / refuse | Fire I selected; cleared with `""`. Frost III refused (`locked`). A form node id and a number both refused (`unknown_infusion`). |
| Snapshot | `basicAttackInfusion = { id = "fire.fire_1", potency = 1.02 }` at Fire level 2; 1.16 at level 16. |
| Generic rule | Rapid Jabs with Fire I on the dummy split each hit into Physical and Fire. The numbers match exactly: 25% conversion at ×1.02, plus Studio's test modifier (see Notes). |
| Element XP | Each infused swing: +1 Fire (use); each training hit: +2 Fire, in the trunk (Fire I's branch). |
| Fireball | The wand with Fire III resolves Mana Ball → Fireball. The projectile spawns with `element = Fire`, `scale = 1.8`, `impactScale = 4`. The direct hit dealt 23.09, all Fire. A second enemy took exactly 60% (13.86) from the explosion. Reach and Spread each gained XP from the join credit. |
| Canvas | Mana Ball reads "IN USE · FIREBALL" and Fire III reads "IN USE · FIREBALL". Clicking Fire III cleared it, and clicking again selected it (real canvas clicks). |
| Looks | Fireball trail embers render in Fire orange. The orb and its impact were not caught on screen. |

The dev save was put back afterwards: Fire trunk 22.38, no infusion, wand unequipped.

## Notes

- **Studio registers test modifiers on the player** (`server/Testing`, printed at startup as "Fire
  Conversion 30%"). They add their own Physical → Fire conversion on top of an infusion, so infused
  damage looks larger in Studio than the rule alone gives.
- **To check by eye:** the Fireball orb and explosion, Frost colours, and the melee element burst.
- **The place file has an old, unregistered Slime model** in Workspace at (23, 0, 15.5). It has the
  pre-fix layout (RootPart, AnimationController), like the stray Dummy removed earlier.
- **Not in this step:**
  - passive effects (Ignite, Chill and the rest still do nothing);
  - attunement-only end nodes' effects;
  - the other six combinations, which wait on their shapes;
  - a second cost resource.
