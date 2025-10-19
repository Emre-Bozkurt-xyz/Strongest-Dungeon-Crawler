# Legacy NetRay Channel Inventory

Historical snapshot of every NetRay dependency prior to migrating to the custom dispatcher. The table remains for reference when comparing legacy behavior, auditing telemetry regressions, or explaining intent mappings carried forward into the current transport.

| Channel | Pattern | Server Registration & Handlers | Client Consumers | Priority / Notes |
| --- | --- | --- | --- | --- |
| `StatsDelta` | Event (Server → Client) | `src/server/StatsManager.luau` registers with `priority = NetRay.Priority.LOW`, `batchable = true`; `src/server/RegenerationService.luau` also fires deltas for pool regen | `src/client/StatsClient.luau`, `src/client/ui/controllers/SystemPanelHandler.luau`, `src/client/ui/controllers/StatusPreviewController.luau` | Low priority, batchable; carries stat deltas and regen updates → target envelope: `Event.Stats.Updated` |
| `StatsRequest` | Request (Client → Server) | `src/server/StatsManager.luau` handles full snapshot responses | `src/client/StatsClient.luau` issues requests on init/resync | Used for initial stat sync and manual refresh → target intent: `Intent.Stats.RequestSnapshot` |
| `AttributesDelta` | Event (Server → Client) | `src/server/AttributesManager.luau` registers with `priority = NetRay.Priority.CRITICAL`, `batchable = false` | `src/client/AttributesClient.luau`, `src/client/ui/controllers/SystemPanelHandler.luau` | Critical priority to cut UI latency; embeds trace metadata → target envelope: `Event.Attributes.Updated` |
| `AttributesRequest` | Request (Client → Server) | `src/server/AttributesManager.luau` supplies snapshot | `src/client/AttributesClient.luau` fetches full state on connect/retry | Returns serialized attribute set → target intent: `Intent.Attributes.RequestSnapshot` |
| `AttributesSpendPoint` | Request (Client ↔ Server) | `src/server/AttributesManager.luau` validates point allocation | `src/client/ui/controllers/AttributesUIController.luau` submits spends (HIGH priority) | Includes trace payload for latency tracking → target intent: `Intent.Attributes.SpendPoints` |
| `SkillsEvent` | Event (Server → Client) | `src/server/SkillsFramework/SkillsEvent.luau` registers with `priority = NetRay.Priority.CRITICAL` and broadcasts execution phases | `src/client/SkillsFramework/SkillsClient.luau` forwards to FX/animation systems | CRITICAL priority, non-batch → target envelope: `Event.Skills.Execution` |
| `SkillsRequest` | Request (Client → Server) | `src/server/SkillsFramework/SkillsManager.luau` processes skill usage | `src/client/SkillsFramework/SkillsClient.luau` submits skill requests | Returns success/failure payloads → target intent: `Intent.Skills.Use` |
| `CooldownEvents` | Event (Server → Client) | `src/server/SkillsFramework/CooldownService.luau` registers (LOW priority, batchable) | `src/client/SkillsFramework/CooldownClient.luau` mirrors cooldown state | Payload types: `cd_start`, `cd_adjust`, `cd_clear`, `cd_snapshot` → target envelope: `Event.Cooldowns.Changed` |
| `CooldownSnapshotRequest` | Request (Client → Server) | `src/server/SkillsFramework/CooldownService.luau` responds with current cooldown map | `src/client/SkillsFramework/CooldownClient.luau` triggers on startup and resync | Used as fallback when deltas missed → target intent: `Intent.Cooldowns.RequestSnapshot` |
| `EntityInfoDelta` | Event (Server → Client) | `src/server/EntityInfoService.luau` registers with `priority = NetRay.Priority.BACKGROUND` | `src/client/EntityInfoClient.luau`, `src/client/EntityRevealStore.luau` | Background priority world metadata updates → target envelope: `Event.Entities.InfoUpdated` |
| `EntityInfoRequest` | Request (Client → Server) | `src/server/EntityInfoService.luau` streams entity snapshots | `src/client/EntityInfoClient.luau`, `src/client/EntityRevealStore.luau` | Provides batched entity data → target intent: `Intent.Entities.RequestInfo` |

## Observations
- Multiple server modules emit on shared channels (e.g., `StatsManager` and `RegenerationService` both publish to `StatsDelta`). The replacement system must support multi-producer semantics per channel and map them to shared domain events.
- Priorities range from BACKGROUND to CRITICAL; replacement must honor similar QoS tiers to preserve UX expectations while using intent names to select defaults.
- Nearly every client module calls `NetRay:RegisterRequestEvent` even when only firing requests, indicating the new API should separate the concepts of subscription vs. caller-friendly helpers and expose simple `Networking.intent("Stats.RequestSnapshot", payload)` helpers.
- Trace/telemetry metadata currently exists only on attribute flows; we should generalize diagnostics in the new transport rather than embedding ad-hoc fields, and leverage it for optional replay logging.
- Each mapping above defines the canonical envelope name, simplifying future logging/replay since events and intents become easy to serialize.

## How to Use This Record Now
- Use the table as a lookup when validating that dispatcher channels preserve the original intent/event semantics.
- Reference the legacy priorities if future QoS adjustments risk regressing UX expectations.
- Keep the document updated only when historical context changes (e.g., new telemetry comparisons) rather than for day-to-day dispatcher work.
