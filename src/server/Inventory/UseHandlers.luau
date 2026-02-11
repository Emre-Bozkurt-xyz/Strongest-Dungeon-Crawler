--!strict
-- Item use handlers (server authoritative).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ItemTypes = require(ReplicatedStorage.Shared.items.ItemTypes)
local StatTypes = require(ReplicatedStorage.Shared.StatTypes)
local StatsManager = require(ServerScriptService.Server.Stats.StatsManager)

local UseHandlers = {}

type UseHandler = (entityId: string, item: ItemTypes.ItemInstance, def: ItemTypes.ItemDef) -> (boolean, string?)

local handlersByAction: { [string]: UseHandler } = {}

handlersByAction["ManaPotion"] = function(entityId, item, def)
	local meta = def.metadata or {}
	local poolName = meta.restorePool or StatTypes.PoolStats.Mana
	local amount = meta.restoreAmount or 25
	local ok = StatsManager.addToResource(entityId, poolName, amount)
	if not ok then
		return false, "resource_failed"
	end
	return true, nil
end

function UseHandlers.apply(entityId: string, item: ItemTypes.ItemInstance, def: ItemTypes.ItemDef): (boolean, string?)
	local action = def.useAction
	if not action then
		if def.category == "consumable" then
			return false, "no_handler"
		end
		return true, nil
	end
	local handler = handlersByAction[action]
	if not handler then
		return false, "no_handler"
	end
	return handler(entityId, item, def)
end

return UseHandlers
