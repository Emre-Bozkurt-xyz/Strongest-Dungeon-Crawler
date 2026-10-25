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
- `emit` sends events to one or more targets, adding QoS metadata for the transport stats. Omitting
  `targets` sends to every player; an explicit list — even an empty one — sends to exactly those
  players.
- `request` (available on both peers) performs an RPC via the channel’s `RemoteFunction`.

QoS is recorded in envelope metadata and transport stats only. Every channel is a reliable
`RemoteEvent`; nothing is dropped or reordered by QoS.

## Channel Guidelines

- Skills use the `Skills` channel (`CRITICAL` QoS) for server authority over combo events.
- Stats use the `Stats` channel, defaulting to `HIGH` QoS for responsive UI.
- `EntityInfo` carries presence (2 Hz snapshots) and vitals (per-frame health changes); see
  `docs/client/entity-presence.md`.
- `Combat` `HitEvent`s go only to players near the target plus the source and target players, with a
  trimmed result (`totalDamage`, `byType`, `crit`, `dodged`, `blocked`, `staggerApplied`).
- `FX` relays client-played effects and sounds (`FXEvent`, `SFXEvent`) to other players in range,
  never back to the sender.
- `Loadout` carries skill slot set commands as requests (`LoadoutCommand`, `LoadoutSnapshot`) and
  pushes the whole loadout (`LoadoutUpdate`) when a save loads.

## Gotchas

- On the server, `meta.playerId` of anything a client sent is overwritten with the remote's actual
  sender. The envelope is client-written, so a playerId it carries is only a claim; before this was
  enforced, FX relay and `RequestShoot` ownership could be spoofed as another player. Handlers may
  trust `meta.playerId` on the server; a request's `context.player` is the same player.

- Requiring `Networking` from a Studio command/MCP context during a playtest constructs a second
  Dispatcher, which rebinds every `RemoteFunction.OnServerInvoke` and breaks requests for the rest
  of the session. Probe from those contexts with raw remotes and instances only.

When adding a new system, define a channel entry in `Channels.luau`, then call `_ensureChannel` before the first `emit`/`request`. This will create remotes on the server and wait for them on the client.

## Replay and Diagnostics

`Dispatcher` can keep a replay buffer if configured (`replay = { enabled = true, bufferSize = ... }`). Use it when debugging ordering issues or verifying QoS throttling. Stats counters are available via `dispatcher._stats:snapshot()` to surface transport health in tooling.
