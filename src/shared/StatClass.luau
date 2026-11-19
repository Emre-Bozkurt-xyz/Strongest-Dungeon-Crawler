-- One stat: a base value, the modifiers laid over it, and the clamped, cached final value.
--
-- The base has two layers so that setting it never loses where it came from. The default
-- (`defaultValue`) is what the stat was built with -- the game default in StatsConfig -- unless the
-- entity's definition set its own (`setBaseValue`, an NPC spec's configure step), after which the
-- stat no longer follows the game default (`ownsDefault`). An override (`overrideValue`) replaces the
-- default for a session (dev tooling, tests) and can be cleared, which brings back the default as it
-- is by then. `baseValue` is the effective base, override else default; modifiers, pools and
-- replication read only that, so the layers are invisible downstream and to the client mirror.

local Stat = {}
Stat.__index = Stat

export type StatConfig = {
	baseValue: number,
	minValue: number?,
	maxValue: number?,
	name: string,
	description: string?,
}

function Stat.new(config: StatConfig)
	local self = setmetatable({
		statType = "static", -- Identify this as a static stat
		name = config.name,
		baseValue = config.baseValue,
		defaultValue = config.baseValue,
		overrideValue = nil :: number?,
		ownsDefault = false,
		minValue = config.minValue or 0,
		maxValue = config.maxValue or math.huge,
		description = config.description,
		modifiers = {},
		_cachedValue = nil,
		_isDirty = true,
		_modifierCounter = 0,
	}, Stat)

	return self
end

-- Add a modifier to this stat
local function getPriority(modifier): number
	if modifier and typeof(modifier) == "table" then
		return modifier.priority or 0
	end
	return 0
end

local function getOrderKey(modifier): number
	if modifier and typeof(modifier) == "table" then
		return modifier._orderKey or 0
	end
	return 0
end

function Stat:addModifier(modifier)
	self._modifierCounter += 1
	if typeof(modifier) == "table" then
		modifier._orderKey = self._modifierCounter
	end
	table.insert(self.modifiers, modifier)
	self:_sortModifiers()
	self:_markDirty()
end

function Stat:_sortModifiers()
	table.sort(self.modifiers, function(a, b)
		local pa, pb = getPriority(a), getPriority(b)
		if pa ~= pb then
			return pa < pb
		end
		local oa, ob = getOrderKey(a), getOrderKey(b)
		return oa < ob
	end)
end

-- Remove a modifier by source_id
function Stat:removeModifier(source_id: string): boolean
	for i, modifier in ipairs(self.modifiers) do
		if modifier.source_id == source_id then
			table.remove(self.modifiers, i)
			self:_markDirty()
			return true
		end
	end
	return false
end

function Stat:updateModifier(source_id: string, newValue: number): boolean
	for _, modifier in ipairs(self.modifiers) do
		if modifier.source_id == source_id then
			modifier:modifyValue(newValue)
			self:_markDirty()
			return true
		end
	end
	warn(`Modifier '{source_id}' not found in {self.name}`)
	return false
end

-- Get all modifiers from a specific source
function Stat:getModifiersFromSource(source_id: string)
	local result = {}
	for _, modifier in ipairs(self.modifiers) do
		if modifier.source_id == source_id then
			table.insert(result, modifier)
		end
	end
	return result
end

-- Calculate the final value with all modifiers
function Stat:getValue(allStats: any?): number
	if not self._isDirty and self._cachedValue then
		return self._cachedValue
	end

	-- Start with base value
	local finalValue = self.baseValue

	-- Apply modifiers using their apply method
	for _, modifier in ipairs(self.modifiers) do
		if modifier.apply then
			finalValue = modifier:apply({
				lastValue = finalValue,
				baseValue = self.baseValue,
				stat = self,
				stats = allStats,
			})
		else
			warn(`Modifier from {modifier.source_id} does not have an apply method`)
		end
	end

	-- Clamp to min/max
	finalValue = math.clamp(finalValue, self.minValue, self.maxValue)

	-- Cache the result
	self._cachedValue = finalValue
	self._isDirty = false

	return finalValue
end

-- Get base value without modifiers
function Stat:getBaseValue(): number
	return self.baseValue
end

function Stat:_refreshBase()
	local base = if self.overrideValue ~= nil then self.overrideValue else self.defaultValue
	if base ~= self.baseValue then
		self.baseValue = base
		self:_markDirty()
	end
end

-- Sets the default as the entity's own: what its definition says this stat starts at. From then on
-- the stat no longer follows the game default. An override, if any, stays in front of it.
function Stat:setBaseValue(value: number)
	self.defaultValue = value
	self.ownsDefault = true
	self:_refreshBase()
end

function Stat:addToBaseValue(amount: number)
	self:setBaseValue(self.defaultValue + amount)
end

function Stat:getDefaultValue(): number
	return self.defaultValue
end

-- Whether the entity's definition set this stat's default, so a change of the game default passes
-- it by.
function Stat:ownsDefaultValue(): boolean
	return self.ownsDefault == true
end

-- Moves the default to a changed game default, unless the entity's definition owns it. Returns
-- whether the default moved.
function Stat:setInheritedDefault(value: number): boolean
	if self.ownsDefault then
		return false
	end
	self.defaultValue = value
	self:_refreshBase()
	return true
end

function Stat:getOverride(): number?
	return self.overrideValue
end

function Stat:setOverride(value: number)
	self.overrideValue = value
	self:_refreshBase()
end

-- Back to the default. Returns whether there was an override.
function Stat:clearOverride(): boolean
	if self.overrideValue == nil then
		return false
	end
	self.overrideValue = nil
	self:_refreshBase()
	return true
end

-- Get modifier breakdown for debugging/UI
function Stat:getModifierBreakdown(): { { name: string, value: number, type: string, source: string } }
	local breakdown = {}

	for _, modifier in ipairs(self.modifiers) do
		if modifier.isActive then
			local context = {
				lastValue = self.baseValue,
				baseValue = self.baseValue,
				stat = self,
				stats = nil,
			}
			local modifiedValue = modifier:apply(context)
			local contribution = modifiedValue - self.baseValue

			table.insert(breakdown, {
				name = modifier.description or modifier.source_id,
				value = contribution,
				type = modifier.type or "unknown",
				source = modifier.source_id,
			})
		end
	end

	return breakdown
end

-- Mark the cached value as dirty
function Stat:_markDirty()
	self._isDirty = true
end

-- Force cache invalidation (useful when external systems modify this stat)
function Stat:invalidateCache()
	self:_markDirty()
end

return Stat
