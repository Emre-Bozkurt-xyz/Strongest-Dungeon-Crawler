# Networking Layer Overview

The project uses a custom dispatcher built on Roblox remotes. Shared modules live under `src/shared/Networking/`.

## Dispatcher Basics

- `Dispatcher.luau` abstracts `RemoteEvent` / `RemoteFunction` usage. It tracks QoS buckets, latency stats, and optional replay buffers.
- `ChannelRegistry.luau` and `Channels.luau` define available channels, their direction (`client_to_server`, `server_to_client`, `bidirectional`), and remote names.
- `Networking.init`, `Networking.client`, and `Networking.server` produce singleton dispatchers on each peer.

## Sending and Receiving

```lua
local Networking = require(ReplicatedStorage.Shared.Networking)
local dispatcher = Networking.server()

dispatcher:on("StatsDelta", function(payload, meta)
	-- handle incoming client events
end)

dispatcher:emit("EntityInfoDelta", payload, {
	targets = player,
	qos = "BACKGROUND",
})
```

- `on` registers event listeners.
- `onRequest` registers request/response handlers. The context argument exposes `player` for server calls.
- `emit` sends events to one or more targets, adding QoS metadata for the transport stats.
- `request` (available on both peers) performs an RPC via the channel’s `RemoteFunction`.

## Channel Guidelines

- Skills use the `Skills` channel (`CRITICAL` QoS) for server authority over combo events.
- Stats use the `Stats` channel, defaulting to `HIGH` QoS for responsive UI.
- Entity presence uses `EntityInfo` with `BACKGROUND` QoS because updates can be dropped and refreshed regularly.

When adding a new system, define a channel entry in `Channels.luau`, then call `_ensureChannel` before the first `emit`/`request`. This will create remotes on the server and wait for them on the client.

## Replay and Diagnostics

`Dispatcher` can keep a replay buffer if configured (`replay = { enabled = true, bufferSize = ... }`). Use it when debugging ordering issues or verifying QoS throttling. Stats counters are available via `dispatcher._stats:snapshot()` to surface transport health in tooling.
