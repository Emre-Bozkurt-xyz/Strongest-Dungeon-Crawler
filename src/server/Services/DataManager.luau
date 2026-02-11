--!strict
-- DataManager (stub): no-op persistence layer for early integration.

local DataManager = {}

function DataManager.loadPlayerData(_playerId: string): any?
	return nil
end

function DataManager.savePlayerData(_playerId: string, _data: any)
	-- no-op
end

function DataManager.loadInventory(_playerId: string): any?
	return nil
end

function DataManager.saveInventory(_playerId: string, _data: any)
	-- no-op
end

return DataManager
