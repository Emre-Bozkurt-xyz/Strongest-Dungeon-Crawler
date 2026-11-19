--!strict
-- Game defaults tuned live: change a stat's default base value (StatsConfig) mid-session, see it on
-- every live entity at once, and export the numbers to paste into the file.
--
-- A tuned value is laid over the file's for this server only (StatsConfig.setSessionDefault) and is
-- gone when Play stops. That is the point: nothing persists it, so a tuned value can never become a
-- hidden setting that disagrees with StatsConfig.luau. Keeping a value means writing it in the file.
--
-- A change reaches new registrations (StatsConfig builds them) and every live entity that inherits
-- the default (StatsManager.applyGameDefault). It passes by an entity whose own definition set that
-- stat (an NPC spec's configure step) and leaves any override in front of the default in place; a
-- pool whose maximum moves keeps its current value within the new maximum, never refilled.

local ServerScriptService = game:GetService("ServerScriptService")

local Server = ServerScriptService.Server
local StatsConfig = require(Server.Stats.Config.StatsConfig)
local StatsManager = require(Server.Stats.StatsManager)

local GameDefaults = {}

export type Row = {
	stat: string,
	kind: string,
	-- The value written in StatsConfig.luau.
	file: number,
	-- The value new entities get now.
	value: number,
	changed: boolean,
	min: number,
	max: number,
}

export type Change = {
	stat: string,
	kind: string,
	-- StatsConfig's table and the key the entry sits under in it.
	table: string,
	key: string,
	field: string,
	file: number,
	value: number,
	-- The whole entry with the new value, ready to replace the old one.
	line: string,
}

local TABLE_OF: { [string]: string } = {
	pool = "DEFAULT_POOLS",
	static = "DEFAULT_STATS",
	resource = "DEFAULT_RESOURCES",
}

local TYPES_OF: { [string]: string } = {
	pool = "Types.PoolStats",
	static = "Types.StaticStats",
	resource = "Types.ResourceStats",
}

-- Leading fields in the order StatsConfig writes them; any others follow sorted.
local FIELD_ORDER = { "baseValue", "minValue", "maxValue", "name", "description" }

-- A JSON-safe limit: math.huge cannot cross the remote.
local function finite(value: number): number
	return if math.abs(value) == math.huge then (if value > 0 then 1e308 else -1e308) else value
end

local function luauValue(value: any): string
	if type(value) == "string" then
		return string.format("%q", value)
	end
	return tostring(value)
end

local function entryLine(stat: string, kind: string, value: number): string
	local config = (StatsConfig :: any)[TABLE_OF[kind]][stat]
	local fields: { string } = {}
	local seen: { [string]: boolean } = {}
	local function add(field: string, fieldValue: any)
		seen[field] = true
		if fieldValue ~= nil then
			table.insert(fields, `{field} = {luauValue(fieldValue)}`)
		end
	end
	for _, field in ipairs(FIELD_ORDER) do
		add(field, if field == "baseValue" then value else config[field])
	end
	local rest: { string } = {}
	for field in pairs(config) do
		if not seen[field] then
			table.insert(rest, field)
		end
	end
	table.sort(rest)
	for _, field in ipairs(rest) do
		add(field, config[field])
	end
	return `[{TYPES_OF[kind]}.{stat}] = \{ {table.concat(fields, ", ")} },`
end

-- The stat as StatsConfig names it, matched without regard to case; nil when there is none.
function GameDefaults.resolve(name: string): string?
	local lowered = string.lower(name)
	for _, stat in ipairs(StatsConfig.names()) do
		if string.lower(stat) == lowered then
			return stat
		end
	end
	return nil
end

function GameDefaults.row(stat: string): Row
	local min, max = StatsConfig.limitsOf(stat)
	local file = StatsConfig.fileDefault(stat) :: number
	local value = StatsConfig.defaultOf(stat) :: number
	return {
		stat = stat,
		kind = StatsConfig.kindOf(stat) :: string,
		file = file,
		value = value,
		changed = value ~= file,
		min = finite(min),
		max = finite(max),
	}
end

-- Every default, sorted by name.
function GameDefaults.list(): { Row }
	local rows: { Row } = {}
	for _, stat in ipairs(StatsConfig.names()) do
		table.insert(rows, GameDefaults.row(stat))
	end
	return rows
end

export type SetResult = Row & StatsManager.DefaultChange & { clamped: boolean }

-- Sets the default of `stat` for this session (the file's own value clears it) and moves every live
-- entity that inherits it. The value is clamped to the stat's limits.
function GameDefaults.set(stat: string, value: number): (SetResult?, string?)
	local name = GameDefaults.resolve(stat)
	if not name then
		return nil, `no stat named '{stat}'`
	end
	if value ~= value or math.abs(value) == math.huge then
		return nil, "the value must be a finite number"
	end
	local min, max = StatsConfig.limitsOf(name)
	local clamped = math.clamp(value, min, max)
	local file = StatsConfig.fileDefault(name)
	if not StatsConfig.setSessionDefault(name, if clamped == file then nil else clamped) then
		return nil, "game defaults can only be tuned in a dev session"
	end
	local change = StatsManager.applyGameDefault(name :: any, clamped)
	local result = GameDefaults.row(name) :: any
	result.inherited = change.inherited
	result.overridden = change.overridden
	result.ownDefault = change.ownDefault
	result.clamped = clamped ~= value
	return result, nil
end

-- Back to the file's value: one stat, or every changed one when `stat` is nil. Returns the stats
-- that were reset.
function GameDefaults.reset(stat: string?): ({ string }?, string?)
	local names: { string }
	if stat then
		local name = GameDefaults.resolve(stat)
		if not name then
			return nil, `no stat named '{stat}'`
		end
		names = { name }
	else
		names = {}
		for name in pairs(StatsConfig.sessionDefaults()) do
			table.insert(names, name)
		end
		table.sort(names)
	end
	local reset: { string } = {}
	for _, name in ipairs(names) do
		if StatsConfig.sessionDefaults()[name] ~= nil then
			StatsConfig.setSessionDefault(name, nil)
			StatsManager.applyGameDefault(name :: any, StatsConfig.fileDefault(name) :: number)
			table.insert(reset, name)
		end
	end
	return reset, nil
end

-- The changed defaults as StatsConfig.luau entries, each replacing the entry of the same key in its
-- table, and as a list of the changes. Empty when nothing is changed.
function GameDefaults.export(): (string, { Change })
	local changes: { Change } = {}
	for _, row in ipairs(GameDefaults.list()) do
		if row.changed then
			table.insert(changes, {
				stat = row.stat,
				kind = row.kind,
				table = `StatsConfig.{TABLE_OF[row.kind]}`,
				key = `{TYPES_OF[row.kind]}.{row.stat}`,
				field = "baseValue",
				file = row.file,
				value = row.value,
				line = entryLine(row.stat, row.kind, row.value),
			})
		end
	end
	local blocks: { string } = {}
	for _, kind in ipairs({ "pool", "static", "resource" }) do
		local lines: { string } = {}
		for _, change in ipairs(changes) do
			if change.kind == kind then
				table.insert(lines, `-- {change.stat}: {change.file} in the file`)
				table.insert(lines, change.line)
			end
		end
		if #lines > 0 then
			table.insert(blocks, `-- StatsConfig.{TABLE_OF[kind]}\n{table.concat(lines, "\n")}`)
		end
	end
	return table.concat(blocks, "\n\n"), changes
end

return GameDefaults
