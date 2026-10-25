# Entity Presence & Vitals

What each player is told about the entities around them, and how the client turns it into enemy
health bars and hit reactions.

## Server: EntityInfoService

`src/server/Services/EntityInfoService.luau` owns the `EntityInfo` channel and sends two streams:

| Event | Rate | Contents | Purpose |
|---|---|---|---|
| `EntityInfoDelta` | 2 Hz | Every entity within the viewer's `PerceptionDistance`: `id`, `kind`, `name`, plus health at the viewer's `PerceptionTier` | Membership, and the backstop for health changes vitals do not report |
| `EntityVitals` | once per frame, only when something changed | `id` + health for entities whose Health pool changed this frame | Health bars move the frame after a hit |

Reveal tiers: tier 1 reveals `hpPerc`, tier 2 adds `hp = { current, max }`.

Rules:

- Presence decides who may see what. Vitals are sent only to viewers whose latest presence
  included the entity, at the tier that presence used — they never widen visibility.
- Vitals are driven by `StatsManager.onPoolChanged`, which reports discrete pool writes for every
  entity (damage, heals, modifiers, base changes). Continuous regeneration writes pools directly and
  is carried by presence instead; at 30 Hz it would turn vitals into a per-frame stream.
- Presence is sent even when empty so the client can retire entities that left range.

## Client: EntityStore

`src/client/Entities/EntityStore.luau` is the single client view of nearby entities.

- `start()` binds both events (called from `Bootstrap`).
- `getSnapshot()` / `onChanged(cb)` — immutable list of entries, republished only when something
  drawn changes. Each entry has `id`, `kind`, `name`, `health?` (`current?`, `max?`, `ratio`),
  `anchor?` (the HumanoidRootPart, once streamed in) and `present`.
- Entities missing from presence are kept, not present, for 1 s before hiding and 4 s before being
  dropped, so a bar flickering at the edge of perception does not rebuild.
- `isAlive(id)` — false only when the server revealed zero health; unknown counts as alive.
- `markStruck(id)` / `getStruckAt(id)` — local, predicted strikes. Never touch health.

## Enemy health bars

`src/client/ui/panels/EnemyBars` draws a bar for every entry with revealed health. The value is
always the server's; a predicted strike (`markStruck`) only jolts the bar sideways for ~0.18 s so
the hit registers on the frame it lands, and the cells drop when vitals confirm the damage.

## Predicted melee reactions

See `src/shared/skills/MeleeHits.luau` and `src/client/fx/PredictedHits.luau`: melee hits share one
definition of timing and cone between peers, so the client flashes the target, plays the hit sound,
applies hitstop and marks the strike on the same schedule the server resolves damage. Damage numbers
and health stay on server confirmation (`HitEvent`, `EntityVitals`).
