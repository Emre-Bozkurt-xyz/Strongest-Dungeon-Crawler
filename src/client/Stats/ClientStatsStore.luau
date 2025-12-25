--!strict
-- ClientStatsStore: centralized, readonly facade over client stats + skill metadata
-- Provides simple query helpers for UI/prediction without exposing dispatcher details.

local ClientStatsStore = {}

local StatsClient = require(script.Parent.Parent.StatsClient)
local SkillMetadataClient = require(script.Parent.Parent.SkillsFramework.SkillMetadataClient)

-- Pools
function ClientStatsStore.getPoolCurrent(poolType: string): number?
	return StatsClient.getPoolCurrent(poolType)
end

function ClientStatsStore.getPoolMax(poolType: string): number?
	return StatsClient.getPoolMax(poolType)
end

function ClientStatsStore.getPool(poolType: string): { current: number?, max: number? }?
	local current = StatsClient.getPoolCurrent(poolType)
	local max = StatsClient.getPoolMax(poolType)
	if current == nil and max == nil then
		return nil
	end
	return { current = current, max = max }
end

-- Metadata
function ClientStatsStore.getSkillMetadata(skillName: string)
	return SkillMetadataClient.get(skillName)
end

-- Can the local player afford this skill (optionally a combo step)?
-- Returns table with cost info and affordability flag for convenience.
function ClientStatsStore.canAfford(
	skillName: string,
	step: number?
): {
	affordable: boolean,
	cost: number?,
	resource: string?,
	current: number?,
	max: number?,
}
	local metadata = SkillMetadataClient.get(skillName)
	local cost: number? = nil
	local resource: string? = nil
	if metadata then
		if step and metadata.comboCosts then
			cost = metadata.comboCosts[step]
		elseif metadata.cost then
			cost = metadata.cost
		end
		resource = metadata.costResource
	end

	local current: number? = nil
	local max: number? = nil
	if resource then
		current = StatsClient.getPoolCurrent(resource)
		max = StatsClient.getPoolMax(resource)
	end

	local affordable = false
	if cost and resource then
		if current ~= nil then
			affordable = current + 1e-3 >= cost
		end
	else
		-- If we lack metadata, stay pessimistic but return false with whatever we know
		affordable = false
	end

	return {
		affordable = affordable,
		cost = cost,
		resource = resource,
		current = current,
		max = max,
	}
end

-- Placeholder for future tempo prediction mirror; returns nil for now to keep API stable.
function ClientStatsStore.getPredictedTempo(_skillName: string)
	return nil
end

-- Pass-through subscribe hooks for UI convenience
function ClientStatsStore.onStatsChanged(callback)
	return StatsClient.onChanged(callback)
end

return ClientStatsStore
