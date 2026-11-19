--!strict
-- CommandRegistry: one definition per dev command, runnable from any entry point (in-game console,
-- Studio command bar, scripts). The registry has no knowledge of the game; each realm owns an
-- instance and fills it with the commands that realm can execute. A command line never throws at the
-- caller: every outcome, including a crashing handler, comes back as a Result.
--
-- Handlers return nothing, a string (the message), or a table `{ message, data, ok }`. `ok = false`
-- reports a failure the handler understood; for a failure raised from deep inside a helper, call
-- `CommandRegistry.fail`, which unwinds to the registry without a traceback. Any other error is
-- treated as a bug in the command and keeps its traceback.

local CommandLine = require(script.Parent.CommandLine)

local CommandRegistry = {}
CommandRegistry.__index = CommandRegistry

export type Realm = "server" | "client"

export type Context = {
	player: Player?,
	realm: Realm,
}

export type Result = {
	ok: boolean,
	message: string,
	data: any?,
}

export type ArgDef = CommandLine.ArgDef

export type CommandDef = {
	-- One or two words; matched case-insensitively, longest name first.
	name: string,
	-- Grouping label for listings.
	group: string,
	summary: string,
	args: { ArgDef }?,
	run: (context: Context, args: { [string]: any }) -> any,
}

-- Plain data, safe to send over a remote.
export type ArgDescriptor = {
	name: string,
	type: CommandLine.ArgType,
	optional: boolean,
	default: any?,
	choices: { string }?,
	min: number?,
	max: number?,
}

export type Descriptor = {
	name: string,
	group: string,
	summary: string,
	usage: string,
	realm: Realm,
	args: { ArgDescriptor },
}

type Registry = {
	realm: Realm,
	commands: { [string]: CommandDef },
	-- Word count of the longest registered name, which bounds the dispatch lookahead.
	maxWords: number,
}

export type CommandRegistry = typeof(setmetatable({} :: Registry, CommandRegistry))

local MAX_SUGGESTIONS = 3

local function normalizeName(name: string): string
	local words: { string } = {}
	for word in string.gmatch(string.lower(name), "%S+") do
		table.insert(words, word)
	end
	return table.concat(words, " ")
end

local function wordCount(key: string): number
	local _, spaces = string.gsub(key, " ", "")
	return spaces + 1
end

local function editDistance(a: string, b: string): number
	local lengthA, lengthB = #a, #b
	if lengthA == 0 then
		return lengthB
	end
	if lengthB == 0 then
		return lengthA
	end
	local previous: { number } = {}
	for j = 0, lengthB do
		previous[j] = j
	end
	for i = 1, lengthA do
		local current: { number } = { [0] = i }
		for j = 1, lengthB do
			local cost = if string.byte(a, i) == string.byte(b, j) then 0 else 1
			current[j] = math.min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
		end
		previous = current
	end
	return previous[lengthB]
end

-- Raised from inside a handler to report a failure the user caused (bad target, missing state).
function CommandRegistry.fail(message: string): never
	error({ commandFailure = true, message = message }, 0)
end

function CommandRegistry.new(realm: Realm?): CommandRegistry
	local self: Registry = {
		realm = realm or "server",
		commands = {},
		maxWords = 1,
	}
	return setmetatable(self, CommandRegistry)
end

function CommandRegistry.register(self: CommandRegistry, def: CommandDef)
	assert(type(def) == "table", "command def must be a table")
	assert(type(def.name) == "string" and def.name ~= "", "command def needs a name")
	local key = normalizeName(def.name)
	assert(key ~= "", `command '{def.name}' has an empty name`)
	assert(type(def.group) == "string" and def.group ~= "", `command '{key}' needs a group`)
	assert(type(def.summary) == "string", `command '{key}' needs a summary`)
	assert(type(def.run) == "function", `command '{key}' needs a run function`)
	assert(self.commands[key] == nil, `command '{key}' is already registered`)

	local args = def.args or {}
	local seen: { [string]: boolean } = {}
	local sawOptional = false
	for index, arg in ipairs(args) do
		assert(type(arg.name) == "string" and arg.name ~= "", `command '{key}' argument {index} needs a name`)
		assert(not seen[arg.name], `command '{key}' repeats argument '{arg.name}'`)
		seen[arg.name] = true
		assert(CommandLine.ARG_TYPES[arg.type], `command '{key}' argument '{arg.name}' has unknown type '{arg.type}'`)
		assert(arg.type ~= "rest" or index == #args, `command '{key}': 'rest' must be the last argument`)
		assert(arg.type ~= "choice" or arg.choices ~= nil, `command '{key}' argument '{arg.name}' needs choices`)
		local optional = CommandLine.isOptional(arg)
		assert(optional or not sawOptional, `command '{key}': required argument '{arg.name}' follows an optional one`)
		sawOptional = sawOptional or optional
	end

	self.commands[key] = def
	self.maxWords = math.max(self.maxWords, wordCount(key))
end

function CommandRegistry.get(self: CommandRegistry, name: string): CommandDef?
	return self.commands[normalizeName(name)]
end

-- Matches the longest registered name at the start of `text`. Returns the command and the text after
-- its name.
local function resolve(self: CommandRegistry, text: string): (CommandDef?, string)
	local words: { { word: string, nextPosition: number } } = {}
	local position = 1
	for _ = 1, self.maxWords do
		local token, nextPosition, err = CommandLine.nextToken(text, position)
		if token == nil or err then
			break
		end
		table.insert(words, { word = string.lower(token), nextPosition = nextPosition })
		position = nextPosition
	end
	for count = #words, 1, -1 do
		local parts: { string } = {}
		for index = 1, count do
			parts[index] = words[index].word
		end
		local def = self.commands[table.concat(parts, " ")]
		if def then
			return def, string.sub(text, words[count].nextPosition)
		end
	end
	return nil, ""
end

-- The command `text` would run, without running it.
function CommandRegistry.find(self: CommandRegistry, text: string): CommandDef?
	local def = resolve(self, text)
	return def
end

local function suggest(self: CommandRegistry, text: string): { string }
	local tokens = CommandLine.tokenize(text)
	local typedFirst = string.lower(tokens[1] or "")
	local typedPair = string.lower(table.concat(tokens, " ", 1, math.min(#tokens, 2)))
	if typedFirst == "" then
		return {}
	end
	local threshold = math.max(2, #typedFirst // 3)

	local scored: { { name: string, score: number } } = {}
	for key in pairs(self.commands) do
		local firstWord = string.match(key, "^%S+") :: string
		local score: number
		if string.find(key, typedFirst, 1, true) then
			score = 0
		else
			score = math.min(editDistance(typedFirst, firstWord), editDistance(typedPair, key))
		end
		if score <= threshold then
			table.insert(scored, { name = key, score = score })
		end
	end
	table.sort(scored, function(a, b)
		if a.score ~= b.score then
			return a.score < b.score
		end
		return a.name < b.name
	end)

	local names: { string } = {}
	for index = 1, math.min(#scored, MAX_SUGGESTIONS) do
		names[index] = scored[index].name
	end
	return names
end

-- Registered names close to what `text` starts with, best first.
function CommandRegistry.suggest(self: CommandRegistry, text: string): { string }
	return suggest(self, text)
end

local function toResult(value: any): Result
	if value == nil then
		return { ok = true, message = "ok" }
	end
	if type(value) == "string" then
		return { ok = true, message = value }
	end
	if type(value) == "table" then
		local message = value.message
		return {
			ok = value.ok ~= false,
			message = if type(message) == "string" then message else "ok",
			data = value.data,
		}
	end
	return { ok = true, message = tostring(value) }
end

local function onHandlerError(err: any): any
	if type(err) == "table" and err.commandFailure == true then
		return err
	end
	return debug.traceback(tostring(err), 2)
end

function CommandRegistry.run(self: CommandRegistry, text: string, context: Context): Result
	if type(text) ~= "string" or string.match(text, "^%s*$") then
		return { ok = false, message = "empty command" }
	end

	local def, argsText = resolve(self, text)
	if not def then
		local typed = CommandLine.tokenize(text)[1] or text
		local suggestions = suggest(self, text)
		local message = `unknown command '{typed}'`
		if #suggestions > 0 then
			message ..= `. Did you mean: {table.concat(suggestions, ", ")}?`
		end
		return { ok = false, message = message }
	end

	local args = def.args or {}
	local parsed, parseError = CommandLine.parse(argsText, args, CommandLine.usage(normalizeName(def.name), args))
	if not parsed then
		return { ok = false, message = parseError or "invalid arguments" }
	end

	local ok, value = xpcall(def.run, onHandlerError, context, parsed)
	if not ok then
		if type(value) == "table" and value.commandFailure == true then
			return { ok = false, message = tostring(value.message) }
		end
		return { ok = false, message = tostring(value) }
	end
	return toResult(value)
end

local function describeDef(self: CommandRegistry, def: CommandDef): Descriptor
	local args = def.args or {}
	local argDescriptors: { ArgDescriptor } = {}
	for _, arg in ipairs(args) do
		table.insert(argDescriptors, {
			name = arg.name,
			type = arg.type,
			optional = CommandLine.isOptional(arg),
			default = arg.default,
			choices = if arg.choices ~= nil then CommandLine.resolveChoices(arg) else nil,
			min = arg.min,
			max = arg.max,
		})
	end
	local name = normalizeName(def.name)
	return {
		name = name,
		group = def.group,
		summary = def.summary,
		usage = CommandLine.usage(name, args),
		realm = self.realm,
		args = argDescriptors,
	}
end

function CommandRegistry.describe(self: CommandRegistry): { Descriptor }
	local list: { Descriptor } = {}
	for _, def in pairs(self.commands) do
		table.insert(list, describeDef(self, def))
	end
	table.sort(list, function(a, b)
		if a.group ~= b.group then
			return a.group < b.group
		end
		return a.name < b.name
	end)
	return list
end

return CommandRegistry
