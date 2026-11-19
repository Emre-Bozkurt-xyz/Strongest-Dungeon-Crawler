--!strict
-- Commands that change the calling player's own state: resource pools and the bag.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemEnums = require(ReplicatedStorage.Shared.items.ItemEnums)
local ItemRegistry = require(ReplicatedStorage.Shared.items.Registry)
local StatTypes = require(ReplicatedStorage.Shared.StatTypes)
local Support = require(script.Parent.Parent.CommandSupport)

local HEAL_POOLS = { "Health", "Mana", "Stamina" }

local function poolNames(): { string }
	local names: { string } = {}
	for name in pairs(StatTypes.PoolStats) do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

local function itemIds(): { string }
	local ids: { string } = {}
	for _, def in ipairs(ItemRegistry.list()) do
		table.insert(ids, def.id)
	end
	return ids
end

-- In rarity order rather than alphabetical, which is how a person reads them.
local RARITIES: { string } = {
	ItemEnums.Rarity.Normal,
	ItemEnums.Rarity.Magic,
	ItemEnums.Rarity.Rare,
	ItemEnums.Rarity.Unique,
}

local function describePool(playerId: string, pool: string): string
	local stats = Support.load("Stats.StatsManager")
	local current = stats.getPoolCurrentValue(playerId, pool)
	local max = stats.getPoolMaxValue(playerId, pool)
	return string.format("%s %s/%s", pool, tostring(current and math.floor(current + 0.5)), tostring(max and math.floor(max + 0.5)))
end

return {
	{
		name = "pool",
		group = "Player",
		summary = "Add to (positive) or remove from (negative) one of your resource pools",
		args = {
			{ name = "pool", type = "choice", choices = poolNames },
			{ name = "delta", type = "number" },
		},
		run = function(context, args)
			local _, playerId = Support.playerEntity(context)
			local stats = Support.load("Stats.StatsManager")
			local pool: string = args.pool
			local delta: number = args.delta
			local changed = if delta >= 0
				then stats.addToPool(playerId, pool, delta)
				else stats.removeFromPool(playerId, pool, -delta)
			if changed == false then
				Support.fail(`could not change {pool} (no such pool for this entity)`)
			end
			return describePool(playerId, pool)
		end,
	},
	{
		name = "heal",
		group = "Player",
		summary = "Refill your Health, Mana and Stamina",
		run = function(context)
			local _, playerId = Support.playerEntity(context)
			local stats = Support.load("Stats.StatsManager")
			local lines: { string } = {}
			for _, pool in ipairs(HEAL_POOLS) do
				local current = stats.getPoolCurrentValue(playerId, pool)
				local max = stats.getPoolMaxValue(playerId, pool)
				if current and max and max > current then
					stats.addToPool(playerId, pool, max - current)
				end
				table.insert(lines, describePool(playerId, pool))
			end
			return table.concat(lines, ", ")
		end,
	},
	{
		name = "give",
		group = "Player",
		summary = "Add an item to your bag",
		args = {
			{ name = "itemId", type = "choice", choices = itemIds },
			{ name = "count", type = "integer", default = 1, min = 1 },
			{ name = "rarity", type = "choice", optional = true, choices = RARITIES },
		},
		run = function(context, args)
			local _, playerId = Support.playerEntity(context)
			local inventory = Support.load("Inventory.InventoryService")
			local itemId: string = args.itemId
			local count: number = args.count
			local rarity: string? = args.rarity
			local meta = if rarity then { rarity = rarity } else nil
			if not inventory.addItem(playerId, itemId, count, meta) then
				Support.fail(`could not add {count}x {itemId} (unknown item or no room)`)
			end
			return `gave {count}x {itemId}{if rarity then ` ({rarity})` else ""}`
		end,
	},
	{
		name = "drop",
		group = "Player",
		summary = "Drop the first bag items in front of you, to check the loot labels",
		args = {
			{ name = "count", type = "integer", default = 1, min = 1 },
		},
		run = function(context, args)
			local _, playerId = Support.playerEntity(context)
			local inventoryService = Support.load("Inventory.InventoryService")
			local inventory = inventoryService.getInventory(playerId)
			if not inventory then
				Support.fail("you have no inventory")
			end
			local count: number = args.count
			local dropped = 0
			for slot = 1, inventory.capacity do
				local uid = inventory.slots[slot]
				if uid and dropped < count then
					inventoryService.dropItem(playerId, uid)
					dropped += 1
				end
			end
			return `dropped {dropped} item(s)`
		end,
	},
}
