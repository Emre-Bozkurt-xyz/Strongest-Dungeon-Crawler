# Animations

## Where clips live

A clip belongs to the thing that plays it, and is declared in that owner's own module under
`animations`:

| Owner | Module | Full key |
|---|---|---|
| Attack profile (a moveset) | `src/shared/skills/BasicAttackProfiles/<id>.luau` | `<id>/<clip>` |
| Skill | `src/shared/skills/Specs/<Skill>.luau` | `<Skill>/<clip>` |

```lua
animations = {
	slash_1 = "rbxassetid://123", -- published
	idle = false,                 -- declared, not published yet
},
steps = { { animation = "sword_light_1h/slash_1", ... } },
```

Every reference uses the full key, including inside the owner, so a key means the same thing in a
profile step, a skill spec or an item's `animationOverrides`. A skill can play another owner's clip
(Punch plays `unarmed_basic/punch_1`).

`Shared.Animation.AnimationRegistry` gathers every owner's clips at load and warns once about any
reference no owner declares. The client's `AssetLoader` builds one `Animation` per published clip;
nothing reads `ReplicatedStorage.Assets.Animations` any more.

Weapon clips belong to the profile, not the weapon item: every sword sharing `sword_light_1h`
swings the same way. An item that should look different overrides keys through
`capabilities.animationOverrides`.

Character specs (`src/shared/Characters/`) still hold raw IDs, since NPC playback reads them on the
server without a key.

## Drafts and publishing

An animation only plays in a live server if the game's owner (or Roblox) owns it, so every clip is
published from the owner's account.

1. **Draft.** Save the KeyframeSequence in `ServerStorage.RBX_ANIMSAVES` named by its full key
   (`sword_light_1h/slash_1`). Placeholder clips are under `RBX_ANIMSAVES.AnimRig_R6`; the rig they
   load onto is `ServerStorage.AnimationRigs.AnimRig_R6` (drag it into Workspace to use the
   Animation Editor).
2. **Playtest.** In Studio, a declared clip with no published ID plays its draft:
   `server/dev/AnimationDrafts` copies matching saves to `ReplicatedStorage.AnimationDrafts` and the
   client registers them under temporary IDs. The output lists which drafts are standing in. Live
   servers never do this.
3. **Publish.** Animation Editor → Publish to Roblox, or from a script with
   `AssetService:CreateAssetAsync(kfs:Clone(), Enum.AssetType.Animation, { Name = <full key>,
   CreatorId = <game owner>, CreatorType = ... })` (a Studio beta feature that has to be switched
   on). Then put the ID in the owner's `animations` table in place of `false`. A published ID
   always wins over a draft.

## Placeholder authoring

`tools/anim-authoring/` builds the placeholder clips from pose tables (`Clips.luau`) so they can be
regenerated after a tweak; how to run it is at the top of `AnimAuthoring.luau`. Placeholders pose
the upper body only, so the walk cycle keeps playing under an attack.
