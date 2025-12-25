# Design Principles: Event Bus, Stats Pipeline, Predicate Framework, Networking

## Purpose
- Capture the north-star goals inspired by Adam Myhre's workflows before altering code.
- Align the team on measurable outcomes, acceptable tradeoffs, and hard constraints.
- Provide an anchor we can revisit after each milestone to confirm scope adherence.

## Desired Outcomes (Measurable)
- Skill, stat, and UI events propagate locally within 30 ms under normal gameplay load.
- Cross-boundary network hops stay below 120 ms round-trip during stress tests (200 concurrent remote calls/minute).
- Shared gameplay modules expose public APIs ≤ 10 functions each, keeping surface areas auditable.
- New predicate-driven behaviors ship with automated validation (unit or integration coverage) ≥ 80% of the predicate leaves.
- Maintain a ≥ 90% reduction in high-priority queue saturation events compared to legacy NetRay telemetry.

## Guiding Architectural Goals
- Favor composition over inheritance: decouple data specs from behavior through event buses and predicate combinators.
- Drive systems via domain events: services publish semantic events (`Stats.Updated`, `Skills.ExecutionStarted`) and subscribe through intent-specific adapters rather than hard references.
- Ensure determinism: predicates, stat calculations, event routing, and transport handling must produce identical outputs for identical inputs.
- Preserve observability: every new subsystem exposes lightweight diagnostics (counts, last emit times, active listeners, channel latency).
- Keep the learning curve low: documentation and examples accompany each new abstraction during rollout.

## Non-Goals and Guardrails
- No runtime reflection or dynamic code injection beyond what Luau natively offers; keep module graphs explicit.
- Avoid expanding Roblox RemoteInstances beyond what the custom networking wrapper requires; no auto-spawned remotes per event.
- Do not alter existing save-data formats or player progression during this wave unless explicitly carved out.
- Refrain from introducing third-party dependencies without review against Roblox performance/security constraints.

## Event Bus Constraints
- One module owns each channel; channels register through a manifest to avoid hidden globals.
- Listener registration/deregistration must be explicit and paired with lifecycle hooks (e.g., `PlayerRemoving`).
- Snapshot listeners before emit to guard against mutation during dispatch; include optional `once` semantics.
- Promote intent-first envelopes: events identify domain action + payload, enabling future replay or off-thread simulation without rewriting consumers.
- Provide opt-in instrumentation: a debug flag surfaces counts and slow listeners without flooding output in production.

## Stats & Modifier Pipeline Principles
- Separate concerns into registry (definitions), modifiers (builders), mediator (aggregation), and consumers (UI, combat).
- Treat modifiers as immutable data; mutation occurs only when mediators rebuild derived values.
- Maintain backwards compatibility: legacy stat configs should migrate via adapters until fully replaced.
- Supply factory helpers mirroring Unity patterns (flat, percent, attribute-scaled) with clear naming and typed payloads.

### Unity Stats & Modifiers Study Notes
- **Mediator caching**: Adam Myhre's `StatsMediator` caches modifier slices by `StatType` and invalidates on mutation, letting queries remain O(n) only when the set actually changes; replicate this to cut redundant recomputation in our `StatsManager`.
- **Operation strategies**: Implement additive/multiplicative math as strategy objects (`AddOperation`, `MultiplyOperation`) to keep modifier data declarative and enable author-friendly factories instead of sprawling conditional logic.
- **Timed modifiers lifecycle**: Countdown timers live on the modifier itself, toggling a `MarkedForRemoval` flag and raising a disposal event; adopt a shared timer utility so stat buffs, status effects, and regen-overrides follow the same lifecycle hooks.
- **Factory + registration**: A simple factory registered at startup decouples pickups/UI from modifier construction—mirror this with module-level factories (no DI container needed) so future systems request modifiers by semantic intent (e.g., `DamageBuffFactory.createPercent(…)`).
- **Visitor-style pickups**: The repo uses a `Pickup` visitor to funnel interactions; document that pattern for our eventual loot/boon system so stats and inventory remain decoupled.

## Predicate Combinator Guidance
- Offer basic leaves that map directly to gameplay checks (alive, range, cone, status, faction).
- Chainable API mirrors Unity example (`Predicates.start(InRange).and(IsAlive)`), returning pure functions for reuse.
- Context objects carry immutable data (origin, target, cached stat snapshots) to ensure stable evaluations.
- Document common recipes (NPC interaction gates, skill targeting, quest triggers) alongside reusable predicate bundles.

## Networking Direction
- Capture legacy NetRay limitations (queueing, inspection difficulty, priority bleed) in a living document for historical comparison and future regressions.
- New transport mirrors event bus semantics: typed channels, explicit QoS tiers, observable queues, and domain-intent messages.
- Keep transport logic thin: it forwards intent envelopes, leaving orchestration and side effects to domain services.
- Instrument every send/receive with latency stamps and counters, stored in a lightweight stats sink for debugging and optional replay logging.
- Preserve the staged migration playbook (coexistence mode, parity tests, final cutover) for future transport upgrades while keeping replay support in mind (e.g., recordable envelopes).

## Command-Driven Skill Execution Vision
- **Single execution queue per actor**: Replace bespoke combo vs single-skill flows with a `CommandManager` that holds queued `SkillCommand` instances, each exposing `canExecute`, `execute`, `cancel`, and lifecycle callbacks.
- **Composable commands**: Model combo chains as composite commands that enqueue their own steps, letting per-step delays, resource checks, and FX scheduling live inside the command rather than scattered across services.
- **Deterministic gating**: Commands are enqueued only after shared gating (cooldowns, resources, combo windows) pass; once queued, they own execution, call into `SessionManager` for session transitions, and raise domain events for UI/FX observers.
- **Extensibility hooks**: By standardizing lifecycle events (`onQueued`, `onStarted`, `onCompleted`, `onInterrupted`), downstream systems (projectiles, timeline FX, analytics) subscribe without bespoke glue, paving the way for replays or rollback.
- **Migration strategy**: Start by wrapping an existing skill (`Punch`) with a command, prove parity, then incrementally port combos and asynchronous skills; maintain adaptor shims until the legacy path is removed.

## Validation & Feedback Loop
- After each milestone, review metrics against Desired Outcomes; adjust scope if targets drift.
- Maintain a "gotchas" section in documentation to log emerging constraints or Roblox-specific pitfalls.
- Schedule retrospective checkpoints after event bus pilot, stat pipeline refactor, predicate deployment, and networking swap.
