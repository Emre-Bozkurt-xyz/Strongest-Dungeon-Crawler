# Projectile System Revival Plan

Goal: restore projectiles with client prediction (visuals) while keeping server‑authoritative hits, and support dynamic trajectories (homing/chained) without desync.

## Phase 0 — Baseline + scope
- Identify which projectile service is in use (`server/Services/ProjectileService.luau`) and confirm client renderer (`client/Services/ProjectilesClient.luau`).
- Confirm existing skills that spawn projectiles (e.g., `ManaBall`) still route through the service.
- Decide minimal guarantees: server authoritative hit, client visual prediction, no heavy state beacons yet.

## Phase 1 — Guidance + homing (authoritative target selection)
- Extend server spawn params to include `guidance` (homing metadata: targetEntityId, turnRate, maxRange, faction/tag filters).
- Server selects target (closest valid) and includes it in spawn recipe.
- Server sim applies homing each tick (turn‑rate limited).
- Client sim uses the same target id for visuals (no hit authority).

## Phase 2 — Trajectory extensibility (non‑linear)
- Add a shared “movement behavior” contract (update‑step on server + client).
- Add sample chained/curve behaviors (e.g., arc + ease‑out).
- Keep deterministic seeds for any randomness.

## Phase 3 — Sync & correction (optional)
- If visuals diverge too much: add low‑rate “state beacons” from server (pos/vel/targetId).
- Client soft‑corrects (lerp), never snap.

## Phase 4 — Skill integration + tooling
- Provide helper API for skills: `spawnProjectiles(specId, origin, aim, pattern, count)`.
- Add debug toggles for projectile hits, target selection, and sim drift.

Notes:
- Server stays authoritative for hit resolution.
- Client prediction is visual only.
- Homing target selection must be server‑driven to keep results sane and anti‑cheat.
