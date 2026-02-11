# Phase 0 Notes - Architecture Map + Complexity Hotspots

**Date:** 2026-01-25  
**Status:** Draft (Phase 0)

## Entry Points
- Server: `src/server/init.server.luau`
  - Boots Stats, SkillsFramework, StatusEffects, Services, NPC system, SessionManager heartbeat
  - Starts TimeSync responder and EntityInfoService streaming
- Client: `src/client/init.client.luau`
  - Boots TimeSync, SessionMirror, ActionPermissions client, Stats/Attributes clients, UI/controllers
  - Requests initial stats/attributes/skill metadata on spawn

## System Map (High Level)

### Shared Core
- Networking: `src/shared/Networking/*` (ChannelRegistry, Dispatcher, Envelope)
- Skills data: `src/shared/skills/*` (ClientSpec, SessionTypes, SkillTimingResolver)
- Stats/Modifiers: `src/shared/stats/*`, `src/shared/Modifiers/*`
- ActionPermissions: `src/shared/ActionPermissions/*` (client/server gates)

### Server Systems
- SkillsFramework: `src/server/SkillsFramework/*`
  - `SkillsManager` (request handling, gating)
  - `SessionManager` (authoritative session state)
  - `CooldownService`, `SkillTimingService`, `HitboxService`
  - `SkillMetadataService` (server-calculated metadata)
- Stats: `src/server/Stats/*`
  - `StatsManager`, `AttributesManager`, `StatsMediator`
- Combat/Status: `src/server/Services/CombatService`, `src/server/StatusEffects/*`
  - `StatusEffectsService`, blocking effects, `StaggerSystem`
- NPC: `src/server/NPCService/*`
  - `NPCManager`, `ComponentManager`, `NPCSpawner`, component-based behaviors
- Services: `RegenerationService`, `EntityInfoService`, `TimeSyncService`

### Client Systems
- SkillsFramework: `src/client/SkillsFramework/*`
  - Base/Basic skills, SkillPacer, SessionMirror, CooldownClient, SkillMetadataClient
- Animation/FX: `src/client/Animation/*`, `src/client/fx/*`
  - AnimationCoordinator, FXPlayer, Replicator, ImmediateHitFeedback
- Stats/UI: `src/client/StatsClient`, `src/client/AttributesClient`, `src/client/ui/*`

## Key Data Flows
- Skill use: client `BaseSkill.requestUse` -> server `SkillsManager` -> server skill execution -> `SessionManager` emits session state -> client `SessionMirror` updates.
- Stats/attributes: server `StatsManager`/`AttributesManager` -> deltas to client -> UI + local gating.
- Combat results: server `CombatService` emits hit events -> UI feedback (damage numbers, stagger confirmation).

## Complexity Hotspots (Top 5)
1. **Dual gating paths**: client pacing vs server cooldown/lock checks can diverge under latency.
2. **Distributed timing logic**: mix of local clocks, TimeSync offset, and server timestamps.
3. **Debug toggles spread across modules**: hard to enable/disable targeted logging.
4. **Session vs combo legacy overlap**: some paths still assume old combo window behavior.
5. **Registrar/EntityId usage**: multiple systems depend on IDs with different lifetimes/assumptions.

## Improvement Opportunities (Phase 0-1 Targets)
- Centralize time helpers and server-time mapping to reduce drift assumptions.
- Consolidate debug toggles to a shared config to reduce noise and enable targeted tracing.
- Add dev-only schema checks on critical network boundaries (skills + sessions).
- Clarify responsibilities between SessionManager and skills for timing and gating.

## Cleanup Candidates (Obsolete or Redundant)
- Legacy `SkillsRequest` RPC path (removed in Phase 1); only `SkillRequestUse` remains.
- Client ActionPermissions session gating (removed); SkillPacer is sole local gate.
- ComboStateClient (deleted previously; keep removed).
- `_ProjectileService.luau` and SkillsFramework/ProjectileService overlap with Services/ProjectileService (pick one).
- Debug toggles scattered in modules (now centralized by DebugConfig).
- Client-side combo window math in BasicComboSkill (moved into SkillPacer).
- EntityInfoService unused identity registry tables (removed).
- NPCSpawner unused Registrar/ServerScriptService require (removed).
- NPC Combat component stored session listener handle unused (removed binding).

## Baseline Metrics to Capture (Manual)
- Server: SessionManager perf stats (avg tick duration, active count, timeouts).
- Client: SessionMirror perf stats (events received, prediction counts).
- Latency runs: local, 100ms, 400ms (basic combo spam + NPC combat).
