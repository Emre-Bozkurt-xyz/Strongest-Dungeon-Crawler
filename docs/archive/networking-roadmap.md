# Custom Networking System Roadmap

## Background
The custom dispatcher now powers all client↔server communication. NetRay has been fully retired, and gameplay systems (stats, attributes, entity info, skills, cooldowns) run through the shared channel registry. This roadmap tracks the follow-up work needed to harden the transport, surface diagnostics, and unlock replay tooling so we keep the momentum from the migration phase.

## Focus Areas
- Harden the dispatcher with first-class diagnostics (queue depth, failure counts, latency histograms) that feed into developer tooling without impacting production performance.
- Formalize message schemas and validation helpers so envelope contracts stay auditable as new intents/events ship.
- Introduce replay-friendly logging hooks that can capture and later rehydrate envelope streams for debugging or load testing.
- Provide a lightweight test harness to spam channels and verify QoS, retry logic, and instrumentation in isolation.

## Non-Goals
- Re-creating the entirety of NetRay’s batching or middleware stack; only build features that demonstrably support current gameplay needs.
- Supporting arbitrary third-party integrations; the dispatcher remains purpose-built for Strongest Dungeon Crawler.
- Automating schema synchronization across services—contracts stay explicit and type-checked in Luau.

## Functional Enhancements
1. **Diagnostics Layer**: Central counters and timers keyed by channel and intent, exposed via `Networking.stats()` and optional developer console commands.
2. **Schema Registry**: Shared module that defines payload validators and emits helpful errors when invalid data crosses the boundary.
3. **Replay Buffer**: Configurable ring buffer per channel with utilities to dump, persist, and re-inject envelopes for simulations.
4. **QoS Enforcement**: Guardrails ensuring channel metadata and per-intent overrides are respected, with warnings when callers deviate from declared tiers.
5. **Test Harness**: Scriptable spam driver that can run in Studio or automated tests, asserting latency bands and error thresholds.

## Enhancement Plan
1. **Diagnostics & Instrumentation**: Implement counters/timers, integrate with existing services, and add developer-friendly dump commands.
2. **Schema & Validation**: Backfill schema tables for all live intents/events, wire validation into dispatcher send/receive paths, and update docs.
3. **Replay Hooks**: Add optional ring buffer logging plus CLI/UI hooks to export/import captured envelopes.
4. **Stress Harness**: Build a repeatable load script leveraging the dispatcher to spam channels, validating instrumentation and QoS behavior.
5. **Ongoing Governance**: Establish lint/test checks that prevent new channels or intents from skipping registry/validation/instrumentation requirements.

## Success Metrics
- Maintain ≥90% reduction in high-priority queue saturation versus legacy NetRay telemetry.
- Provide latency samples for every CRITICAL/HIGH channel in dev builds with ≤5% overhead.
- Enable replay capture and reinjection for at least one end-to-end skills scenario.
- Gather team feedback confirming the new diagnostics surface actionable insights within one iteration of rollout.

## Open Questions
- Do we need envelope signing or additional spoof protections beyond Roblox security primitives?
- What retention window is practical for replay buffers before memory becomes a concern?
- Should retries continue with exponential backoff or use intent-specific strategies based on observed failure patterns?

## Next Actions
- Add instrumentation scaffolding to `Networking` modules and expose a developer-only stats dump.
- Define schema validator stubs for all current intents/events and phase in enforcement.
- Prototype replay buffer hooks on a single channel (e.g., Skills) and validate with a short Studio play session.
