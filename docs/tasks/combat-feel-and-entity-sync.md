# Combat Feel & Entity Sync

## Goal

Make hits feel immediate and make enemy health bars react on the server's confirmation instead of
on a slow poll. Introduce clear client/server contracts for melee hits so the client can predict
the *reaction* to a hit safely, and clean up the entity info pipeline on both peers.

## Findings (baseline)

- Enemy health only reached clients inside the 2 Hz presence broadcast (`EntityInfoService`), so a
  bar lagged a hit by 0–500 ms plus one-way latency. Nothing pushed health on change: pool writes
  in `StatsManager` only notified the owning player.
- Server melee hits ran `hitDelay` after the request *arrived*, so they were always half a round
  trip behind the client's swing, and confirmation added the other half.
- Client hit feedback came from animation markers named in the skill spec (`Punch_Land`). Weapon
  animations (`Sword_1H_*`, `Dagger_1H_*`) do not exist in `Assets/Animations` yet and TripleStrike's
  hit timeline lived only in server data, so most melee had no immediate feedback at all.
- The client cone read the spec's fixed 65°/6 instead of the weapon profile's cone (dagger 45°/4.5),
  and tested HRP distance where the server tests part bounds.
- `BasicAttack` collected its cone with `debug = true`, spawning neon parts every swing.
- Server `Registrar.getEntityId`/`getPlayerId` were linear scans, used per target in every hitbox
  query and per entity per viewer per presence tick.
- `HitEvent` went to every player in the server with the full internal result table.
- `EntityInfoClient` and the `EntityInfoRequest` RPC had no callers.
- QoS labels on channels are metadata only; every channel is a reliable RemoteEvent.

## Current decisions

1. Health bars move only on server confirmation. Prediction drives reactions (flash, hit sound,
   hitstop, bar pulse), never numbers or values -- dodge/crit/mitigation are server rolls.
2. Vitals are a separate, event-driven stream on the `EntityInfo` channel (`EntityVitals`): pool
   changes mark an entity dirty, and dirty entities flush once per frame to viewers that saw them
   at the last presence tick. Presence stays at 2 Hz and still carries health as a backstop.
3. Presence stays on a reliable remote: UnreliableRemoteEvent caps payloads at ~900 bytes, which a
   presence snapshot of a handful of GUID-keyed entities exceeds.
4. Server hits for player casts are scheduled from the client's `inputTime`, not arrival. The lead
   is capped by the player's measured `GetNetworkPing()` and an absolute ceiling, so a forged
   timestamp can shave at most the player's real latency off a wind-up. NPCs send no input time
   and are unaffected. Hit *validation* (server cone on server positions) is unchanged.
5. Melee hit timing and shape are shared contracts (`shared/skills/MeleeHits`), read by both peers:
   profile steps derive them from `combo.hitDelays` + the step/profile cone; TripleStrike's
   timeline moves into its shared spec. The cone test itself lives in one shared module.
6. Client impact timing comes from the same `hitDelay` the server uses, not from animation markers.
   Markers remain for FX only.
7. Hitstop applies to melee contact hits (cone delivery), not projectiles. Local only.
8. One client entity store replaces `EntityInfoClient` + `EntityRevealStore` + `EnemyHealthClient`.

## TODO

- [x] Server Registrar: O(1) reverse lookups; one live entity per player.
- [x] Remove per-request `print` in SkillsManager; hitbox debug draw behind the `hitboxes` flag.
- [x] StatsManager: `onPoolChanged` for every entity.
- [x] EntityInfoService: presence tick + per-frame vitals flush; unused RPC removed; one entity scan
      per tick instead of one per viewer.
- [x] Client `Entities/EntityStore` (presence + vitals + strikes); EnemyBars reads it;
      `EntityInfoClient`, `EntityRevealStore`, `EnemyHealthClient` removed.
- [x] Server input lead (`BaseSkill:resolveInputLead`) in BaseComboSkill (hit + completion) and
      TripleStrike (hits).
- [x] `shared/skills/MeleeHits`: hit contracts + the one cone query; HitboxService cone delegates.
- [x] `client/fx/PredictedHits` + `Hitstop`: scheduled from hitDelay against the shared cone.
- [x] Marker-driven hit detection, `ClientHitDetection`, `hitConeAngle/Range`, `isHitMarker` removed.
- [x] HitEvent: relevance-filtered audience, trimmed payload.
- [x] Docs: entity-presence, networking overview.
- [x] TimeSync on the engine clock: server publishes `ServerClockBias`, client reads
      `GetServerTimeNow() + bias`; the `TimeSync` RemoteFunction channel is gone.
- [x] SkillPacer left an emptied pending table behind after a confirmed step, which read as
      "still pending" and refused the next press (`combo_pending`) for up to 2 s.
- [ ] Developer confirms in Studio (validation plan below).

## Validation plan

Studio, with Network settings > Incoming Replication Lag at ~0.1 s for the latency checks.

1. Unarmed, sword, dagger basic attack on the Dummy: flash + hit sound + hitstop on the swing's
   impact frame; damage numbers and bar move shortly after; no neon hitbox parts.
2. Swing at nothing / out of range: no flash, no hitstop.
3. Dagger at 5 studs (outside its 4.5 cone, inside the old 6): no predicted flash, no damage.
4. TripleStrike with a sword: three predicted impacts with alternating yaw.
5. Regen on an NPC moves its bar without a hit (within 0.5 s, via presence).
6. Walk out of perception range: bar hides, then drops.
7. Wand basic attack: projectile unchanged, no hitstop.
8. A second player near the fight hears the attacker's cast and hit sounds.

## Results / notes

Verified by playtest (unarmed, no lag), timed from the press of a combo step:

| t | event |
|---|---|
| +0.332 s | predicted flash on target (authored hitDelay 0.32) |
| +0.333 s | hitstop on, ~70 ms |
| +0.397 s | `HitEvent` and `EntityVitals` in the same frame -- bar moves with the damage number |

Previously the bar trailed the damage number by 0–500 ms (the presence tick).

Also fixed while here:

- `NPCManager.unregister` passed an entityId to `Registrar.unregisterEntity` (expects a Model) and
  errored.
- Respawned characters left the old entity id mapped to the player.
- Dispatcher sent to *everyone* when given an empty target list.
- FXReplicator had no `SFXEvent` relay (other players never heard cast/hit sounds), echoed FX back
  to the sender (`exclude` is not a Dispatcher option, `meta.player` is never set), and trusted the
  client-supplied `entityId`.

TimeSync, under 0.1 s Studio replication lag (Play Solo shares one process, so the client's own
`os.clock()` is the true server clock to compare against):

| | estimate error | server-measured press-to-handling |
|---|---|---|
| RTT/2 sampler (before) | ~0.4 s ahead | -0.404 s (impossible; clamped to 0) |
| `GetServerTimeNow() + bias` | 2.8 ms | 0.126 s (lag + a frame or two) |

Studio limitations found:

- `Player:GetNetworkPing()` returns 0 in Studio even with replication lag, so the input lead is 0
  there and hit timing matches the pre-change behavior. Validate the lead on a live/team-test server.
- Requiring Networking from an MCP/command context mid-playtest hijacks `OnServerInvoke`; see the
  gotcha in `docs/networking/overview.md`.

## Basic attack pacing (second pass)

Fighting the test NPC felt like "stunlock, then stand around". Causes found:

- `BasicAttack` had a 2 s cooldown (and a 1 s GCD the client applied locally). Letting the combo
  window lapse ends the session as `COMPLETED`, so a single jab followed by a pause locked the
  attack for ~3 s.
- Early presses were dropped: the next step was only accepted once the current step's animation
  (plus a 0.1 s `stepDelay` on unarmed) finished.
- Every hit staggered the Dummy/Slime for 1.5 s, so they never acted during a combo and then
  recovered while the attacker sat on cooldown. No knockback existed to end an exchange.

Decisions:

1. The basic attack has no cooldown and no GCD. It is what a character does between skills, so any
   lockout is dead time whenever skills are also cooling down. Pacing comes from the combo itself.
2. `combo.recovery` is end lag held after the final step's animation, separate from
   `stepDurations` (which set animation playback length, so folding end lag in would slow the
   swing). Both peers compute it: `BaseComboSkill` completion and `SkillPacer` `holdDuration`.
3. Input buffering is client-only (`BasicComboSkill`): a press refused for a reason that clears by
   itself (`combo_busy`, `combo_complete`, `combo_pending`, `locked`) within 0.25 s is held and
   replayed when it would be accepted, 30 ms after the window opens so it cannot reach the server
   ahead of the server's own window. The server's validation is unchanged.
4. Knockback is an attack packet (`distance`, `duration`, optional `direction`; omitted direction
   means away from the attacker, resolved per target). Profile steps opt in with `knockback`; the
   finisher of each melee profile has one. NPCs are pushed by the server (`MovementService`); a
   player is pushed by their own client from the knockback carried on `HitEvent`, since they own
   their character's physics. Both use the dash curve, flattened to the ground plane.
5. Stagger is a flinch: 0.45 s on Dummy/Slime, 0.5 s on players (with the 1 s stagger cooldown,
   players always get a window between staggers).

Not yet: cancelling a step into the next once its hit has landed (before its animation ends), and
client-predicted knockback on the attacker's screen (NPC pushes currently show one round trip late).

## Follow-ups (not in this pass)

- **Mispredicted reach.** With lag the client can predict a hit the server misses, since each side
  sees the other's position one-way late. Options: small server-side reach slack for player
  casters, or rewinding target positions by the input lead. A balance decision; revisit after beta
  testing with real players.
- **TripleStrike completion** is still timed from request arrival (hits are not), so its lock ends
  one-way latency after the client expects.
- Weapon animations (`Sword_1H_*`, `Dagger_1H_*`, `TripleStrike_*`) are not in `Assets/Animations`;
  those attacks play no animation, so they get flash/sound but no hitstop until they exist.
- Legacy Punch/SinglePunch have no shared hit definitions and so no prediction; Punch is ungranted,
  SinglePunch is NPC-only.
- NPCs have no death handling at 0 health; `EntityStore.isAlive` stops predicted reactions on a
  0-health target but the NPC keeps acting.
