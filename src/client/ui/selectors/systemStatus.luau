--!strict
-- Derives the SystemPanel view model from raw stats/attributes data.
--
-- Pure: takes the StatsClient/AttributesClient snapshots in, returns a plain table the component
-- renders. Combat/recovery stats are read through the shared ClientSpec rather than hardcoded here,
-- so a new stat gets a row for free the moment it is added to that spec.
--
-- The old panel only ever surfaced HP/MP/Stamina and the five attributes -- Armor, the damage
-- totals, crit and the regen rates were computed server-side and replicated but never shown. They
-- are added here (R12): the data already exists and costs nothing extra to display, and it is the
-- same improvement ItemCard made by surfacing weapon stats the old inspect panel never showed.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StatTypes = require(ReplicatedStorage.Shared.StatTypes)
local ClientSpec = require(ReplicatedStorage.Shared.stats.ClientSpec)
local AttributesClient = require(script.Parent.Parent.Parent.AttributesClient)

local Selector = {}

export type VitalView = {
	label: string,
	current: number,
	max: number,
	ratio: number,
}

export type AttributeRow = {
	id: string,
	label: string,
	-- The three-letter form the panel actually shows ("STR"). The long name stays for tooltips.
	short: string,
	icon: string,
	base: number,
	bonus: number,
	total: number,
}

-- Level, class and title. Nothing feeds these yet -- no progression system exists -- but they are
-- part of the panel's layout and are shown as placeholders rather than omitted, so the block does
-- not collapse and the intent stays visible.
export type IdentityView = {
	level: number?,
	class: string?,
	title: string?,
}

export type StatRow = {
	label: string,
	value: string,
}

export type SystemView = {
	identity: IdentityView,
	vitals: { VitalView },
	availableAP: number,
	attributes: { AttributeRow },
	combatStats: { StatRow },
	recoveryStats: { StatRow },
}

-- Matches the grid order the Studio panel used (docs/ui/SystemPanel.rbxmx AttributesPanel children,
-- LayoutOrder 0..4), kept for continuity even though the surrounding layout is redesigned.
-- Icons are the ones the Studio panel used, read out of docs/ui/SystemPanel.rbxmx.
local ATTRIBUTES = {
	{ id = "Strength", label = "Strength", short = "STR", icon = "rbxassetid://123083589110121" },
	{ id = "Intelligence", label = "Intelligence", short = "INT", icon = "rbxassetid://83943048570344" },
	{ id = "Dexterity", label = "Dexterity", short = "DEX", icon = "rbxassetid://81054939938377" },
	{ id = "Perception", label = "Perception", short = "PER", icon = "rbxassetid://94712920476240" },
	{ id = "Defense", label = "Defense", short = "DEF", icon = "rbxassetid://86779926667123" },
}

local VITALS = {
	{ key = "Health", label = "HP" },
	{ key = "Mana", label = "MP" },
	{ key = "Stamina", label = "Stamina" },
}

local function formatNumber(value: number): string
	if math.abs(value - math.floor(value + 0.5)) < 1e-6 then
		return tostring(math.floor(value + 0.5))
	end
	return string.format("%.1f", value)
end

local function formatStat(value: number, format: string?): string
	if format == "percent" then
		return `{math.floor(value * 100 + 0.5)}%`
	elseif format == "regen" then
		return `+{formatNumber(value)}/s`
	elseif format == "int" then
		return tostring(math.floor(value + 0.5))
	end
	return formatNumber(value)
end

local function buildVital(stats: StatTypes.PlayerStats?, key: string, label: string): VitalView?
	if not stats then
		return nil
	end
	local pool = (stats :: any)[key]
	if type(pool) ~= "table" or type(pool.getCurrentValue) ~= "function" or type(pool.getValue) ~= "function" then
		return nil
	end
	local ok, current, max = pcall(function()
		return pool:getCurrentValue(), pool:getValue()
	end)
	if not ok or type(current) ~= "number" or type(max) ~= "number" or max <= 0 then
		return nil
	end
	return {
		label = label,
		current = current,
		max = max,
		ratio = math.clamp(current / max, 0, 1),
	}
end

-- Static stats are grouped and ordered by ClientSpec rather than declared here, so Combat/Recovery
-- stay accurate as that spec grows.
local function buildStatGroup(stats: StatTypes.PlayerStats?, group: string): { StatRow }
	local rows: { StatRow } = {}
	if not stats then
		return rows
	end

	local specced: { { name: string, order: number, label: string, format: string? } } = {}
	for _, name in ipairs(StatTypes.AllStaticStatNames) do
		local spec = ClientSpec.get(name)
		if spec and spec.group == group then
			table.insert(specced, { name = name, order = spec.order or 0, label = spec.label, format = spec.format })
		end
	end
	table.sort(specced, function(a, b)
		return a.order < b.order
	end)

	for _, entry in ipairs(specced) do
		local stat = (stats :: any)[entry.name]
		if type(stat) == "table" and type(stat.getValue) == "function" then
			local ok, value = pcall(function()
				return stat:getValue()
			end)
			if ok and type(value) == "number" then
				table.insert(rows, { label = entry.label, value = formatStat(value, entry.format) })
			end
		end
	end
	return rows
end

-- Exposed separately so a panel that only needs HP/MP/Stamina -- StatusPreviewPanel, an ambient
-- overlay with no attribute display -- can read vitals without paying for buildStatGroup's ClientSpec
-- walk over stats it never shows.
function Selector.buildVitals(stats: StatTypes.PlayerStats?): { VitalView }
	local vitals: { VitalView } = {}
	for _, spec in ipairs(VITALS) do
		local vital = buildVital(stats, spec.key, spec.label)
		if vital then
			table.insert(vitals, vital)
		end
	end
	return vitals
end

function Selector.buildView(stats: StatTypes.PlayerStats?, attributes: AttributesClient.AttributesData?): SystemView
	local vitals = Selector.buildVitals(stats)

	local attributeRows: { AttributeRow } = {}
	for _, spec in ipairs(ATTRIBUTES) do
		local entry = attributes and (attributes :: any)[spec.id]
		if entry then
			table.insert(attributeRows, {
				id = spec.id,
				label = spec.label,
				short = spec.short,
				icon = spec.icon,
				base = entry.base,
				bonus = entry.bonus,
				total = entry.current,
			})
		end
	end

	return {
		-- Placeholders until a progression system exists to fill them.
		identity = { level = nil, class = nil, title = nil },
		vitals = vitals,
		availableAP = if attributes then attributes.availableAP else 0,
		attributes = attributeRows,
		combatStats = buildStatGroup(stats, "Offense"),
		recoveryStats = buildStatGroup(stats, "Recovery"),
	}
end

return Selector
