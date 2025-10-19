--!strict
-- Ring buffer to retain recent envelopes for optional replay tooling.

local networkingFolder = script.Parent
local envelopeModuleScript = networkingFolder:FindFirstChild("Envelope")
assert(envelopeModuleScript and envelopeModuleScript:IsA("ModuleScript"), "ReplayBuffer expected sibling ModuleScript 'Envelope'")

local EnvelopeModule = require(envelopeModuleScript)

type Meta = {
	seq: number,
	qos: "CRITICAL" | "HIGH" | "NORMAL" | "BACKGROUND",
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

export type ReplayBuffer = {
	push: (self: ReplayBuffer, envelope: Envelope) -> (),
	iterate: (self: ReplayBuffer) -> { Envelope },
	clear: (self: ReplayBuffer) -> (),
}

type Storage = {
	size: number,
	cursor: number,
	filled: boolean,
	items: { Envelope },
}

local ReplayBuffer = {}
ReplayBuffer.__index = ReplayBuffer

function ReplayBuffer.new(capacity: number?): ReplayBuffer
	local size = capacity or 128
	assert(size > 0, "ReplayBuffer requires a positive capacity")
	local storage: Storage = {
		size = size,
		cursor = 0,
		filled = false,
		items = table.create(size),
	}
	local self = setmetatable(storage, ReplayBuffer) :: any
	return self :: ReplayBuffer
end

local function copyEnvelope(source: Envelope): Envelope
	return EnvelopeModule.clone(source)
end

function ReplayBuffer:push(envelope: Envelope)
	local selfStorage = self :: any
	local storage: Storage = selfStorage
	local nextIndex = (storage.cursor % storage.size) + 1
	storage.items[nextIndex] = copyEnvelope(envelope)
	storage.cursor = nextIndex
	if not storage.filled and nextIndex == storage.size then
		storage.filled = true
	end
end

function ReplayBuffer:iterate(): { Envelope }
	local selfStorage = self :: any
	local storage: Storage = selfStorage
	local result = {}
	if not storage.filled and storage.cursor == 0 then
		return result
	end
	local count = if storage.filled then storage.size else storage.cursor
	local startIndex = if storage.filled then (storage.cursor % storage.size) + 1 else 1
	for i = 0, count - 1 do
		local index = ((startIndex + i - 1) % storage.size) + 1
		local item = storage.items[index]
		if item then
			result[#result + 1] = copyEnvelope(item)
		end
	end
	return result
end

function ReplayBuffer:clear()
	local selfStorage = self :: any
	local storage: Storage = selfStorage
	storage.cursor = 0
	storage.filled = false
	table.clear(storage.items)
end

return ReplayBuffer
