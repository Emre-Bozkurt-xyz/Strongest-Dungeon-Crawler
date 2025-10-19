--!strict
-- EntityInfoClient: Listen to presence deltas and provide simple manual request helpers

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Networking = require(ReplicatedStorage.Shared.Networking)

local ENTITYINFO_CHANNEL_NAME = "EntityInfo"
local dispatcher = Networking.client()
local dispatcherAny = dispatcher :: any
dispatcherAny:_ensureChannel(ENTITYINFO_CHANNEL_NAME)

export type PresenceItem = {
    id: string,
    kind: string, -- "player" | "npc"
    name: string,
    pos: Vector3,
}

local EntityInfoClient = {}

local lastItems: { PresenceItem } = {}
local byId: { [string]: PresenceItem } = {}

local function onDelta(payload: any)
    if not payload or payload.type ~= "presence" then
        return
    end
    local items = payload.items :: { PresenceItem }
    lastItems = items or {}
    table.clear(byId)
    for _, it in ipairs(lastItems) do
        byId[it.id] = it
    end

    -- -- Compact debug print
    -- if #lastItems == 0 then
    --     print("[EntityInfo] No entities nearby.")
    --     return
    -- end
    -- local samples = {}
    -- for i = 1, math.min(3, #lastItems) do
    --     local it = lastItems[i]
    --     table.insert(samples, string.format("%d:%s %s(%s)", i, shortId(it.id), it.name, it.kind))
    -- end
    -- print(string.format("[EntityInfo] %d entities nearby | %s", #lastItems, table.concat(samples, ", ")))
end

dispatcherAny:on("EntityInfoDelta", function(payload)
    onDelta(payload)
end)

function EntityInfoClient.debugDump()
    if #lastItems == 0 then
        print("[EntityInfo] No cached presence items.")
        return
    end
    print("[EntityInfo] Dumping cached presence list:")
    for i, it in ipairs(lastItems) do
        print(string.format("  #%d id=%s name=%s kind=%s pos=(%.1f, %.1f, %.1f)", i, it.id, it.name, it.kind, it.pos.X, it.pos.Y, it.pos.Z))
    end
end

function EntityInfoClient.requestInfo(id: string)
    if type(id) ~= "string" then
        warn("[EntityInfo] requestInfo expects id: string")
        return
    end
    task.spawn(function()
        local ok, resOrErr = pcall(function()
            return dispatcherAny:request("EntityInfoRequest", { id = id }, {
                qos = "BACKGROUND",
            })
        end)
        if not ok then
            warn("[EntityInfo] Request error:", resOrErr)
            return
        end
        local res = resOrErr
        if typeof(res) ~= "table" or not res.ok then
            warn("[EntityInfo] Request failed:", res and res.error)
            return
        end
        print(string.format("[EntityInfo] Info ok id=%s kind=%s name=%s pos=(%.1f, %.1f, %.1f)", res.id, res.kind, res.name, res.pos.X, res.pos.Y, res.pos.Z))
    end)
end

function EntityInfoClient.requestInfoByIndex(index: number)
    if index < 1 or index > #lastItems then
        warn("[EntityInfo] Index out of range")
        return
    end
    local id = lastItems[index].id
    EntityInfoClient.requestInfo(id)
end

function EntityInfoClient.getCache(): { PresenceItem }
    return lastItems
end

return EntityInfoClient
