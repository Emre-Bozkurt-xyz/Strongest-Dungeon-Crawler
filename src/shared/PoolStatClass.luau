--!strict
-- PoolStat class - extends StatClass to add pool functionality (current/max values, reservations)

local Stat = require(game.ReplicatedStorage.Shared.StatClass)

local PoolStat = {}
PoolStat.__index = PoolStat
setmetatable(PoolStat, { __index = Stat })

export type PoolReservation = {
	amount: number,
	type: "flat" | "percent",
	source_id: string,
	description: string,
}

export type PoolConfig = {
	baseValue: number,
	minValue: number?,
	maxValue: number?,
	name: string,
	description: string?,
	startAtMax: boolean?, -- Whether current value starts at max (default: true)
}

function PoolStat.new(config: PoolConfig)
	-- Create base stat first
	local self = Stat.new({
		baseValue = config.baseValue,
		minValue = config.minValue,
		maxValue = config.maxValue,
		name = config.name,
		description = config.description,
	})

	-- Override the metatable to use PoolStat
	setmetatable(self, PoolStat)

	-- Add pool-specific properties
	self.statType = "pool" -- Identify this as a pool stat
	self.currentValue = config.startAtMax ~= false and config.baseValue or 0
	self.reservations = {} :: { PoolReservation }

	return self
end

-- Override _markDirty to also mark max as dirty
function PoolStat:_markDirty()
	self._isDirty = true
	self._maxIsDirty = true
end

-- Get the maximum value (base + modifiers - reservations)
function PoolStat:getMaxAvailableValue(allStats: any?): number
	if not self._maxIsDirty and self._maxCachedValue then
		return self._maxCachedValue
	end

	-- Start with base stat calculation (base + modifiers)
	local maxValue: number = self:getValue(allStats)

	-- Subtract reservations
	for _, reservation in ipairs(self.reservations) do
		if reservation.type == "flat" then
			maxValue = maxValue - reservation.amount
		elseif reservation.type == "percent" then
			maxValue = maxValue - (maxValue * reservation.amount / 100)
		end
	end

	-- Ensure max doesn't go below 0
	maxValue = math.max(0, maxValue)

	-- Cache the result
	self._maxCachedValue = maxValue
	self._maxIsDirty = false

	return maxValue
end

-- Get current value
function PoolStat:getCurrentValue(): number
	return self.currentValue
end

-- Get available value (max - current)
function PoolStat:getAvailableValue(allStats: any?): number
	return self:getValue(allStats) :: number - (self.currentValue :: number)
end

-- Get percentage filled (current / max)
function PoolStat:getPercentage(allStats: any?): number
	local max = self:getValue(allStats)
	if max <= 0 then
		return 0
	end
	return ((self.currentValue :: number) / max) * 100
end

-- Set current value (clamped to 0 and max available after reservations)
function PoolStat:setCurrentValue(value: number, allStats: any?): number
	local max = self:getMaxAvailableValue(allStats) -- Respect reservations
	self.currentValue = math.clamp(value, 0, max)
	return self.currentValue
end

-- Add to current value
function PoolStat:addToCurrentValue(amount: number, allStats: any?): number
	return self:setCurrentValue((self.currentValue :: number) + amount, allStats)
end

-- Remove from current value
function PoolStat:removeFromCurrentValue(amount: number, allStats: any?): number
	return self:setCurrentValue((self.currentValue :: number) - amount, allStats)
end

-- Fill to max
function PoolStat:fillToMax(allStats: any?)
	self.currentValue = self:getValue(allStats)
end

-- Check if empty
function PoolStat:isEmpty(): boolean
	return self.currentValue <= 0
end

-- Check if full
function PoolStat:isFull(allStats: any?): boolean
	return (self.currentValue :: number) >= self:getValue(allStats)
end

-- Add a reservation
function PoolStat:addReservation(reservation: PoolReservation)
	table.insert(self.reservations, reservation)
	self:_markDirty()

	-- Adjust current value if it exceeds new max
	local max = self:getAvailableValue()
	if (self.currentValue :: number) > max then
		self.currentValue = max
	end
end

-- Remove a reservation by source_id
function PoolStat:removeReservation(source_id: string): boolean
	for i, reservation in ipairs(self.reservations) do
		if reservation.source_id == source_id then
			table.remove(self.reservations, i)
			self:_markDirty()
			return true
		end
	end
	return false
end

-- Get all reservations from a specific source
function PoolStat:getReservationsFromSource(source_id: string): { PoolReservation }
	local result = {}
	for _, reservation in ipairs(self.reservations) do
		if reservation.source_id == source_id then
			table.insert(result, reservation)
		end
	end
	return result
end

-- Get total reserved amount
function PoolStat:getTotalReserved(allStats: any?): number
	local baseMax = Stat.getValue(self, allStats)
	local total = 0

	for _, reservation in ipairs(self.reservations) do
		if reservation.type == "flat" then
			total = total + reservation.amount
		elseif reservation.type == "percent" then
			total = total + (baseMax * reservation.amount / 100)
		end
	end

	return total
end

-- Get detailed breakdown for UI/debugging
function PoolStat:getBreakdown(allStats: any?)
	local baseMax = Stat.getValue(self, allStats)
	local totalReserved = self:getTotalReserved(allStats)
	local max = self:getValue(allStats)

	return {
		current = self.currentValue,
		max = max,
		baseMax = baseMax,
		reserved = totalReserved,
		available = self:getAvailableValue(allStats),
		percentage = self:getPercentage(allStats),
		modifiers = self:getModifierBreakdown(),
		reservations = self.reservations,
	}
end

-- Override the modifier breakdown to work with pools
function PoolStat:getModifierBreakdown()
	local breakdown = Stat.getModifierBreakdown(self)

	-- Add reservation breakdown
	local reservationBreakdown = {}
	for _, reservation in ipairs(self.reservations) do
		table.insert(reservationBreakdown, {
			name = reservation.description,
			value = -reservation.amount, -- Negative because it reduces max
			type = reservation.type,
			source = reservation.source_id,
		})
	end

	return {
		modifiers = breakdown,
		reservations = reservationBreakdown,
	}
end

-- Override invalidateCache for pool stats
function PoolStat:invalidateCache()
	self._isDirty = true
	self._maxIsDirty = true
end

-- Get maximum value (alias for getValue for compatibility)
function PoolStat:getMaxValue(allStats: any?): number
	return self:getValue(allStats)
end

return PoolStat
