--!strict
-- Centralized definitions for networking channels shared by client and server.

export type ChannelDefinition = {
	remote: string,
	remoteEvent: string?,
	remoteFunction: string?,
	direction: "server_to_client" | "client_to_server" | "bidirectional",
	qos: "CRITICAL" | "HIGH" | "NORMAL" | "BACKGROUND",
	intents: { string }?,
	events: { string }?,
}

local Channels: { [string]: ChannelDefinition } = {
	DebugEcho = {
		remote = "DebugEcho",
		remoteEvent = "DebugEchoEvent",
		remoteFunction = "DebugEchoInvoke",
		direction = "bidirectional",
		qos = "NORMAL",
		intents = { "DebugEchoIntent" },
		events = { "DebugEchoEvent" },
	},
	Stats = {
		remote = "Stats",
		remoteEvent = "StatsEvent",
		remoteFunction = "StatsRequest",
		direction = "bidirectional",
		qos = "NORMAL",
		intents = { "StatsRequest" },
		events = { "StatsDelta" },
	},
	Attributes = {
		remote = "Attributes",
		remoteEvent = "AttributesEvent",
		remoteFunction = "AttributesRequest",
		direction = "bidirectional",
		qos = "HIGH",
		intents = { "AttributesRequest", "AttributesSpendPoint" },
		events = { "AttributesDelta" },
	},
	Skills = {
		remote = "Skills",
		remoteEvent = "SkillsEvent",
		remoteFunction = "SkillsRequest",
		direction = "bidirectional",
		qos = "CRITICAL",
		intents = { "SkillsRequest" },
		events = { "SkillsEvent" },
	},
	Cooldown = {
		remote = "Cooldown",
		remoteEvent = "CooldownEvents",
		remoteFunction = "CooldownSnapshotRequest",
		direction = "bidirectional",
		qos = "BACKGROUND",
		intents = { "CooldownSnapshotRequest" },
		events = { "CooldownEvents" },
	},
	EntityInfo = {
		remote = "EntityInfo",
		remoteEvent = "EntityInfoEvent",
		remoteFunction = "EntityInfoRequest",
		direction = "bidirectional",
		qos = "BACKGROUND",
		intents = { "EntityInfoRequest" },
		events = { "EntityInfoDelta" },
	},
	Projectiles = {
		remote = "Projectiles",
		remoteEvent = "ProjectileEvent",
		remoteFunction = nil,
		direction = "bidirectional",
		qos = "HIGH",
		-- Intents used for requests from client -> server (RequestShoot) and server -> client responses
		intents = { "RequestShoot", "RequestShootResponse" },
		events = { "ProjectileEvent" },
	},
	FX = {
		remote = "FX",
		remoteEvent = "FXEvent",
		remoteFunction = nil,
		direction = "bidirectional",
		qos = "HIGH",
		intents = nil,
		events = { "FXEvent" },
	},
}

return Channels
