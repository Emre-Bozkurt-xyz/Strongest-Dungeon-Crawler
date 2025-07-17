--!strict
-- Shared types for NetworkManager (both client and server)

export type DeltaData = {
	[string]: any,
}

export type Delta = {
	system: string, -- Which system (stats, attributes, items, etc.)
	type: string, -- Type of change (value_changed, modifier_added, etc.)
	target: string, -- What changed (Health, Intelligence, etc.)
	data: DeltaData, -- The actual change data
	timestamp: number, -- When it happened
}

export type BatchedDeltas = {
	type: "batch",
	system: string,
	deltas: { Delta },
	timestamp: number,
}

export type SystemHandler = {
	deserialize: (data: any) -> any,
	applyDelta: (currentData: any, delta: Delta) -> boolean,
	serialize: (data: any) -> any,
}

return nil -- This is just a types file
