--!strict
-- EntityRevealStore (client): caches presence/reveal deltas and notifies subscribers

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Networking = require(ReplicatedStorage.Shared.Networking)

local ENTITYINFO_CHANNEL_NAME = "EntityInfo"
local dispatcher = Networking.client()
local dispatcherAny = dispatcher :: any
dispatcherAny:_ensureChannel(ENTITYINFO_CHANNEL_NAME)

type PresenceItem = {
    id: string,
    kind: string,
    name: string,
    pos: Vector3,
    hpPerc: number?,
    hp: { current: number, max: number }?,
}

type PresencePayload = {
    type: string, -- "presence"
    items: { PresenceItem },
    ts: number,
}

local EntityRevealStore = {}
EntityRevealStore.__index = EntityRevealStore

local _subscribers: { (PresencePayload) -> () } = {}
local _cache: { [string]: { item: PresenceItem, lastSeen: number } } = {}
local _started = false
local _ttl = 6.0 -- seconds before cached entry is considered stale
local _lastPrune = 0.0
local _disconnect: (() -> ())? = nil

local function _notify(payload: PresencePayload)
    for _, cb in ipairs(_subscribers) do
        task.spawn(cb, payload)
    end
end

local function _onDelta(payload: any)
    if not payload or payload.type ~= "presence" then
        return
    end
    local now = os.clock()
    local items = payload.items :: { PresenceItem }
    for _, it in ipairs(items) do
        _cache[it.id] = { item = it, lastSeen = now }
    end
    -- Always notify, even when list is empty, so consumers can handle hides/destroys
    _notify({ type = "presence", items = items, ts = payload.ts or now })
end

local function _pruneLoop()
    RunService.Heartbeat:Connect(function()
        local now = os.clock()
        if now - _lastPrune < 1.0 then return end
        _lastPrune = now
        for id, rec in pairs(_cache) do
            if now - rec.lastSeen > _ttl then
                _cache[id] = nil
            end
        end
    end)
end

function EntityRevealStore.start()
    if _started then return end
    _started = true
    _disconnect = dispatcherAny:on("EntityInfoDelta", function(payload)
        _onDelta(payload)
    end)
    _pruneLoop()
end

function EntityRevealStore.stop()
    _started = false
    if _disconnect then
        _disconnect()
        _disconnect = nil
    end
    table.clear(_cache)
    table.clear(_subscribers)
end

function EntityRevealStore.onPresence(callback: (PresencePayload) -> ())
    table.insert(_subscribers, callback)
    return function()
        for i, cb in ipairs(_subscribers) do
            if cb == callback then
                table.remove(_subscribers, i)
                break
            end
        end
    end
end

function EntityRevealStore.getLatest(id: string): PresenceItem?
    local rec = _cache[id]
    return rec and rec.item or nil
end

return EntityRevealStore
