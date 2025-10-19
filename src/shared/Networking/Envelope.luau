--!strict
-- Envelope utilities for the custom networking transport.

local Envelope = {}

export type QoS = "CRITICAL" | "HIGH" | "NORMAL" | "BACKGROUND"

export type Meta = {
	seq: number,
	qos: QoS,
	tsSent: number,
	tsAck: number?,
	playerId: number?,
	traceId: string?,
	flags: { [string]: boolean }?,
}

export type Envelope = {
	name: string,
	payload: any,
	meta: Meta,
}

export type CreateOptions = {
	qos: QoS?,
	playerId: number?,
	traceId: string?,
	flags: { [string]: boolean }?,
	tsOverride: number?,
	seqOverride: number?,
}

local DEFAULT_QOS: QoS = "NORMAL"
local seqByName: { [string]: number } = {}

local function nextSeq(name: string): number
	local current = seqByName[name]
	current = (current or 0) + 1
	seqByName[name] = current
	return current
end

function Envelope.create(name: string, payload: any, options: CreateOptions?): Envelope
	assert(type(name) == "string" and name ~= "", "Envelope.create expects a non-empty string name")
	local opts: CreateOptions = options or ({} :: CreateOptions)
	local seqValue = opts.seqOverride
	if seqValue == nil then
		seqValue = nextSeq(name)
	end
	assert(seqValue ~= nil, "Envelope.create: sequence fallback failed")
	local seq: number = seqValue

	local qos: QoS = if opts.qos then opts.qos else DEFAULT_QOS

	local tsValue = opts.tsOverride
	if tsValue == nil then
		tsValue = os.clock()
	end
	assert(tsValue ~= nil, "Envelope.create: timestamp fallback failed")
	local ts: number = tsValue

	local meta: Meta = {
	seq = seq,
		qos = qos,
		tsSent = ts,
		tsAck = nil,
		playerId = opts.playerId,
		traceId = opts.traceId,
		flags = opts.flags,
	}

	return {
		name = name,
		payload = payload,
		meta = meta,
	}
end

function Envelope.clone(envelope: Envelope): Envelope
	local flagsCopy = nil :: { [string]: boolean }?
	local sourceFlags = envelope.meta.flags
	if sourceFlags then
		flagsCopy = {}
		local writable = flagsCopy :: { [string]: boolean }
		for key, value in pairs(sourceFlags) do
			writable[key] = value
		end
	end

	return {
		name = envelope.name,
		payload = envelope.payload,
		meta = {
			seq = envelope.meta.seq,
			qos = envelope.meta.qos,
			tsSent = envelope.meta.tsSent,
			tsAck = envelope.meta.tsAck,
			playerId = envelope.meta.playerId,
			traceId = envelope.meta.traceId,
			flags = flagsCopy,
		},
	}
end

function Envelope.markAck(envelope: Envelope, tsAck: number)
	envelope.meta.tsAck = tsAck
end

function Envelope.resetSequence(name: string?)
	if name then
		seqByName[name] = nil
	else
		for key in pairs(seqByName) do
			seqByName[key] = nil
		end
	end
end

return Envelope
