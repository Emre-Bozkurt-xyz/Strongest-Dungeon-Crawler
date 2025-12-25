---
applyTo: '**'
---
preferences:
  - Keep sending server-determined, deterministic skill metadata to clients for now; defer full client-side resolver/mirror until needed.
  - Maintain a responsive client pool stats mirror (health/mana/stamina bars) for good UX; damage previews are not a priority until UI exists.
  - Whenever new user preferences are given, append them here to keep the assistant's behavior aligned.

recent_implementations:
  - 2025-12-09: SkillAttempt lifecycle fully implemented - client-side attempt tracking with state machine (idle → local_predicted → pending_server → server_confirmed → completed/rejected)
  - 2025-12-09: ClientStatsStore now used for all affordability checks - unified facade over StatsClient + SkillMetadataClient replaces ad-hoc checks
  - 2025-12-09: attemptId propagation complete - flows from client → server → ExecutionService → response, enabling full attempt correlation and debugging
