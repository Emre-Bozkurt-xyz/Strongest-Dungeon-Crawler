# Architecture Refactor Plan Checklist

**Created:** 2026-01-25  
**Status:** Draft  

## Rules of Engagement
- Before beginning each phase, present a short overview of what will be done and the key decisions. Wait for approval before proceeding.
- Keep changes scoped to the active phase; update docs and verify with a short playtest after each phase.

---

## Phase 0 — Baseline + Guardrails
- [x] Phase kickoff: overview + decisions + confirm
- [x] Build a current architecture map (entry points, system ownership, data flow)
- [x] Identify top 5 sources of complexity (legacy + new overlap)
- [x] Add a shared time/clock helper for consistent timestamps
- [x] Add a DebugConfig with dev-only toggles for skills/networking
- [x] Add minimal dev-only schema checks at critical boundaries
- [ ] Capture baseline metrics (perf counters + error rates) (deferred)
- [ ] Short Studio smoke test (no latency, 100ms, 400ms) (deferred)

## Phase 1 — Unified Skill Execution Timeline
- [x] Phase kickoff: overview + decisions + confirm
- [x] Define client vs server responsibilities for skill timing
- [ ] Normalize session state transitions in SessionManager (deferred)
- [x] Remove or isolate legacy gating paths
- [x] Ensure SkillsManager uses a single execution path
- [x] Update migration notes + architecture overview
- [ ] Playtest with latency simulation (deferred)

## Phase 2 — Prediction Controller + Pacing Consolidation
- [x] Phase kickoff: overview + decisions + confirm
- [x] Centralize prediction logic into a PredictionController
- [x] Consolidate pacing into SkillPacer; remove remaining duplication
- [x] Add buffered input and prediction budget (if approved)
- [x] Define accept/reject rules for server validation
- [ ] Update client UX rules and troubleshooting notes

## Phase 3 — Metadata/Tempo Refresh Pipeline
- [x] Phase kickoff: overview + decisions + confirm
- [x] Define metadata caching and refresh cadence
- [x] Add versioning/invalidation for cached skill data
- [x] Ensure client uses server-provided durations/tempo when available
- [x] Add instrumentation counters (stale vs fresh data)
- [ ] Verify under latency simulation

## Phase 4 — NPC/Registrar Cleanup + Service Boundaries
- [x] Phase kickoff: overview + decisions + confirm
- [x] Audit NPCService components and Registrar usage
- [x] Remove dead code and unused connections
- [x] Clarify EntityInfoService ownership for IDs and lookups
- [x] Simplify ActionPermissions and StatusEffects boundaries
- [x] Update docs with new ownership boundaries

## Phase 5 — Bootstrap + Networking Ergonomics
- [x] Phase kickoff: overview + decisions + confirm
- [x] Consolidate init order (server/client entry points)
- [x] Separate dev/test hooks from runtime code
- [x] Tighten networking channel registry + types
- [x] Add startup diagnostics for missing dependencies
- [x] Final docs sweep

---

## Closeout
- [ ] Full playtest matrix (baseline + latency)
- [ ] Update architecture-overview + design principles
- [ ] Archive migration notes and mark completed phases
