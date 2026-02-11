# Custom Networking API Sketch

High-level outline of the modules, types, and call patterns for the new transport. This sketch supplements the roadmap and will evolve into implementation tasks.

## Core Concepts
- **Intent Envelope**: Every message crossing the client/server boundary uses a table of the form:
  ```luau
  type Envelope = {
      name: string, -- e.g. "Intent.Skills.Use" or "Event.Attributes.Updated"
      payload: any, -- schema validated by helper constructors
      meta: {
          seq: number, -- monotonically increasing per channel & peer
          qos: "CRITICAL" | "HIGH" | "NORMAL" | "BACKGROUND",
          tsSent: number, -- os.clock() timestamp at sender
          tsAck?: number, -- filled in on acked responses
          playerId?: number, -- optional origin player UserId
          traceId?: string?,
          flags?: { replayable: boolean?, reliable: boolean? },
      },
  }
  ```
- **Channel Registry**: Declarative table describing all channels, ownership, qos default, and remote binding.
- **Dispatcher**: Thin layer that sends/receives envelopes via Roblox remotes and republishes them to the local event bus.
- **Intent Helpers**: Generated/hand-authored functions that build payloads with validation and call `Networking.intent`.
- **Event Subscriptions**: Consumers subscribe using `Networking.on("Event.Skills.Execution", handler)` and receive validated payloads.

## Module Layout
```text
Networking/
  init.luau              -- bootstrap, returns configured transport
  ChannelRegistry.luau   -- table of channels + metadata
  Envelope.lua           -- constructors, validators, sequence generator
  Dispatcher.lua         -- shared core for client/server
  Client.lua             -- client entrypoint (wrapping Dispatcher)
  Server.lua             -- server entrypoint (wrapping Dispatcher)
  Intents.lua            -- helper functions (generated or maintained manually)
  Events.lua             -- helper subscription wrappers
  Stats.lua              -- instrumentation sink + dump helpers
  ReplayBuffer.lua       -- optional ring buffer for envelopes
```

## Channel Registry Example
```luau
return {
    Stats = {
        remote = "StatsChannel", -- name of RemoteEvent/Function under ReplicatedStorage.Networking
        qos = "LOW",
        direction = "bidirectional", -- or "server_to_client", "client_to_server"
        intents = {
            "Intent.Stats.RequestSnapshot",
        },
        events = {
            "Event.Stats.Updated",
        },
    },
    Attributes = {
        remote = "AttributesChannel",
        qos = "CRITICAL",
        direction = "bidirectional",
        intents = {
            "Intent.Attributes.RequestSnapshot",
            "Intent.Attributes.SpendPoints",
        },
        events = {
            "Event.Attributes.Updated",
        },
    },
}
```

## Public API (Client & Server)
```luau
local Networking = require(ReplicatedStorage.Shared.Networking)

-- Initialize (once)
local transport = Networking.init({
    peer = "client", -- or "server"
    channelRegistry = require(...ChannelRegistry),
    qosOverrides = { -- optional per-channel defaults
        Attributes = "CRITICAL",
    },
    replay = {
        enabled = true,
        bufferSize = 256,
    },
})

-- Send an intent (fire-and-forget)
transport.intent("Intent.Skills.Use", {
    skillId = "TripleStrike",
    traceId = HttpService:GenerateGUID(false),
})

-- Send request/await response
transport.request("Intent.Stats.RequestSnapshot", { version = StatsClient.getLocalVersion() })
    :andThen(function(response)
        -- response.payload = { stats = ... }
    end)
    :catch(function(err)
        warn("Stats snapshot failed", err)
    end)

-- Subscribe to an event
local disconnect = transport.on("Event.Attributes.Updated", function(envelope)
    AttributesClient.applyDelta(envelope.payload)
end)

-- Clean up
transport.disconnect(disconnect) -- or disconnect()

-- Debug dump
transport.stats():dump()
```

### Request/Response Flow
- `transport.request(name, payload, options?)` returns a Promise-like object.
- Options include `timeout`, `retries`, `qosOverride`, `traceId`.
- Dispatcher records pending request keyed by sequence ID; server replies with envelope `Event.<IntentName>.Response` or reuse same name with `meta.isResponse = true`.

### Event Publishing Flow (Server Side)
- Domain services call `transport.emit("Event.Skills.Execution", payload, meta?)`.
- Dispatcher validates payload, stamps metadata (seq, tsSent, qos default), logs to ReplayBuffer when enabled, then fires the remote to subscribed peers.
- Client-side dispatcher receives envelope, verifies sequence (drops or warns on regressions), publishes to client event bus.

## Envelope Validation
- `Envelope.new(name, payload, options)` consults schema tables:
  ```luau
  local Schemas = {
      ["Event.Attributes.Updated"] = Validators.attributesDelta,
      ["Intent.Skills.Use"] = Validators.skillRequest,
  }
  ```
- Validators return `(boolean, string?)`; failing validation raises in dev and returns Promise rejection in release.

## Replay Buffer Hooks
- `ReplayBuffer.push(envelope)` stores a shallow copy (with timestamps) in a ring buffer per channel.
- Future features can expose `Networking.replay(channel, sinceTimestamp)` to feed envelopes back into the dispatcher for local simulation.

## Integration with Event Bus
- Dispatcher publishes received envelopes to the internal bus:
  ```luau
  local EventBus = require(ReplicatedStorage.Shared.EventBus)
  EventBus.emit(name, envelope.payload, envelope.meta)
  ```
- Domain services listen on the bus and orchestrate state changes; networking layer remains transport-only.

## Error Handling & Diagnostics
- `transport.intent` warns when no subscribers exist on target peer (opt-in flag `requireSubscriber`).
- Retries configurable per intent; default for CRITICAL intents is 1 retry with exponential backoff.
- `transport.stats()` exposes aggregated counters per channel and per intent (sent, received, retryCount, avgLatency).
- Optional `transport.setLogger(function(envelope, direction) end)` for custom logging (e.g., to DataStore or file).

## Next Steps
1. Backfill schema definitions for each live intent/event using the current channel registry and document the contracts alongside validator helpers.
2. Harden `Envelope.lua` + dispatcher request handling with diagnostics (latency, retry counters) surfaced through `Networking.stats()`.
3. Integrate optional replay buffer hooks that can capture envelopes per channel and expose dump/replay utilities.
4. Build a dispatcher-focused stress harness that exercises snapshots, spammy deltas, and CRITICAL intents to validate QoS guarantees.
