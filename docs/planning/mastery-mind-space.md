# Mastery Mind-Space — the mastery menu, tree canvas and attunement shrine

Status: **direction agreed 2026-10-27, mockup confirmed; stage 1 (menu and shrine flow) built
2026-10-28.** Art: `src/shared/progression/MasteryArt.luau` (asset ids and crop rects).
It replaces the first-cut canvas (`client/ui/panels/MasteryCanvas`) and the canvas's shrine mode.
The mechanics behind it are in `progression-direction.md`, `docs/tasks/infusions-and-combinations.md`
and `docs/tasks/passives.md`.

## The idea

Opening masteries goes **inside the character's mind**. It is not the System's interface (the
System judges and announces) but the place where the player shapes what they have learned. It
borrows the System's details to stay consistent (bracket corners, type), but it is quieter, darker
and dreamlike.

- **Almost opaque black**, with a faint starfield of slowly blinking lights.
- **Monochrome:** white for what is yours, grey for what is not yet, nothing else. Infusion trees
  may later get a personality of their own (a trace of their element in the stars, the motion, the
  sound). That needs experimentation, so it comes after the monochrome base works.
- **The stars are the fog.** Nodes beyond what the player can see are faint stars. The tree resolves
  into a constellation as they progress.

## Structure

One continuous space with two depths.

1. **Mastery menu.** Boxes floating in the starfield, in two rows by family: weapon masteries
   (Blade, Blunt, Magic, Ranged) and elements (Fire, Frost). The grouping teaches the rule that
   weapon masteries need attunement and elements always work.
   - Each box, minimalist:
     - the mastery's icon in the centre;
     - its name bottom left;
     - a progress bar along the bottom, with progress text bottom right;
     - top right: what the player uses from it (the form or infusion in use).
   - **Attuned masteries** wear embroidery around the box.
   - A thin header shows the limits that apply across all masteries: attunement slots (◆ ◆) and
     selectable passive slots (1 / 2).
2. **Mastery canvas.** Clicking a box zooms into it: the other boxes fall away and its tree resolves
   from the stars. The canvas shows only the tree and a way back, which reverses the zoom.
   Everything else is carried by the tree itself:
   - **Progress lives on the lines.** The grey line toward the next node fills with white as that
     branch earns XP; a Mastered branch's whole line glows.
   - **Newly unlocked nodes pulse** faintly until the player opens them.

## Visual language

| Thing | Look |
|---|---|
| Passive | A plain black circle. Thin white outline when unlocked, grey when locked. No icon. |
| Selectable passive | Slightly larger, with embroidery around it and an icon. Grey when not chosen, white when chosen. |
| Form / infusion | The most important node. Heavier embroidery, an icon, and the System's bracket corners: hidden when not in use, grey when available, white when in use. |
| Attunement-only node | Like a selectable passive, but its embroidery forms a closed ring (it needs the element attuned). |
| Fogged node | A faint star. |
| Earned connection | Thin, clean white line. |
| Line to the next node | Grey, filling with white as the branch earns XP. |

## Interaction

- **Hover** (mouse) previews a node's tooltip. **Click** pins it.
- **The tooltip** is clean and complete:
  - name and kind;
  - for forms and selectable passives, a short lore line;
  - every effect with its **live numbers**: the current value, what it reaches at Mastered, and the
    attuned bonus where one applies;
  - requirements for a locked node;
  - the named combination it would make with the current form;
  - an **action line** (USE THIS FORM, CHOOSE, RELEASE) for nodes that can be acted on.
- **A second click on a pinned node** takes the action. Both routes work with mouse, gamepad and
  touch, and a reflexive double-click on an unpinned node only opens it.
- **Taking an action** plays small particles that burst from the node, slow with drag and fade, with
  a satisfying sound.
- **Form tiers stay separate nodes** (Fire I, II, III). Each is a milestone in the tree, and any
  unlocked tier can be chosen. Fire I at high Fire mastery still gets its potency, so nobody is
  forced into full conversion.

## The attunement shrine

The shrine opens the same mastery menu, in attunement mode.

- **A free slot:** clicking a mastery asks for confirmation, then attunes it.
- **Both slots full:** a **swap**. Pick the mastery to release and the one to attune, then confirm
  both together, with the cost shown. The player never sits with an empty slot halfway through.
- **Cost:** a **world item**, an attunement token found in dungeons and spent at the shrine. The
  first swap or two are free during onboarding. Loot tables must offer it only from mid-game areas
  onward, so early players do not churn attunement before they understand it. Until items and loot
  tables exist, the confirmation shows a placeholder cost line (the cost is data, not UI).

## Technical notes

- **Effect text as data.** Each effect in `NodeEffects` gets a short text template filled with its
  live numbers. The growth maths (branch progress, attunement multiplier) moves into shared code so
  the client computes the same numbers the server applies. Hand-written descriptions would go stale
  when numbers are retuned.
- **Art.** Plain circles, lines, stars, bracket corners and particles are drawn in code. Icons and
  embroidery frames are images generated from the prompts in `mastery-art-prompts.md` and uploaded
  by the developer, referenced by node id from a shared art table. The code falls back to a plain
  look while an image is missing, so the UI is never blocked on art.
- **Performance.** About 150 twinkling stars and short-lived UI particles are negligible.
- **Sound.** New `UISound` cues (node select, form equip, attune), with placeholders until real
  sounds are chosen.

## Build order

0. **Mockup.** An interactive mockup of the menu and a canvas (starfield, node looks, tooltip,
   particles) to confirm the look before any Roblox work, iterated until it is right.
1. **Menu and shrine flow.**
2. **Canvas look and layout.**
3. **Tooltips and effect text.**
4. **VFX and sound.**
5. **Infusion-tree personality** (experimental).
