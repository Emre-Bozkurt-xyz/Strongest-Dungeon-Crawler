--!strict

local ItemInstances = require(script.Parent.Parent.ItemInstances)

local ItemInstanceRepository = {}

function ItemInstanceRepository.create(itemId: string, stackSize: number, meta: { [string]: any }?)
	return ItemInstances.create(itemId, stackSize, meta)
end

function ItemInstanceRepository.get(uid: string)
	return ItemInstances.get(uid)
end

function ItemInstanceRepository.update(uid: string, fields: { [string]: any })
	return ItemInstances.update(uid, fields)
end

function ItemInstanceRepository.remove(uid: string)
	return ItemInstances.remove(uid)
end

function ItemInstanceRepository.list()
	return ItemInstances.list()
end

return ItemInstanceRepository