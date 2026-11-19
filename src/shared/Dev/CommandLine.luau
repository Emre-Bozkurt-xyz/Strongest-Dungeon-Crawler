--!strict
-- CommandLine: turns a typed command line into typed arguments, and a declared argument list into a
-- usage string. Parsing walks the line with a cursor instead of splitting it up front, because the
-- `rest` and `json` argument types need the raw remainder of the line (a JSON literal contains
-- spaces and quote characters that a quote-aware tokenizer would mangle).

local HttpService = game:GetService("HttpService")

local CommandLine = {}

export type ArgType = "string" | "number" | "integer" | "boolean" | "choice" | "json" | "rest"

export type Choices = { string } | () -> { string }

export type ArgDef = {
	name: string,
	type: ArgType,
	optional: boolean?,
	-- A default makes the argument optional.
	default: any?,
	-- `choice` only. A function is resolved each time the choices are needed, so they can follow
	-- live data.
	choices: Choices?,
	-- `number` and `integer` only.
	min: number?,
	max: number?,
}

export type ParsedArgs = { [string]: any }

CommandLine.ARG_TYPES = {
	string = true,
	number = true,
	integer = true,
	boolean = true,
	choice = true,
	json = true,
	rest = true,
} :: { [string]: boolean }

-- Longest choice list quoted in full inside an error or usage line.
local MAX_LISTED_CHOICES = 15
-- Longest static choice list folded into the usage line itself (`<Health|Mana|Stamina>`).
local MAX_INLINE_CHOICES = 6

local TRUE_WORDS = { ["true"] = true, yes = true, on = true, ["1"] = true }
local FALSE_WORDS = { ["false"] = true, no = true, off = true, ["0"] = true }

-- Reads one token starting at or after `from`. Returns the token (nil at end of line), the position
-- to continue from, and an error for an unterminated quote. A token that opens with a quote runs to
-- the matching quote and may contain spaces; `\"`, `\'` and `\\` escape inside it. Quotes in the
-- middle of an unquoted token are ordinary characters.
function CommandLine.nextToken(line: string, from: number): (string?, number, string?)
	local length = #line
	local start = string.find(line, "%S", from)
	if not start then
		return nil, length + 1, nil
	end
	local first = string.sub(line, start, start)
	if first == '"' or first == "'" then
		local buffer: { string } = {}
		local index = start + 1
		while index <= length do
			local char = string.sub(line, index, index)
			if char == "\\" and index < length then
				local following = string.sub(line, index + 1, index + 1)
				if following == first or following == "\\" then
					table.insert(buffer, following)
					index += 2
					continue
				end
			end
			if char == first then
				return table.concat(buffer), index + 1, nil
			end
			table.insert(buffer, char)
			index += 1
		end
		return nil, length + 1, `unterminated {first} quote`
	end
	local finish = string.find(line, "%s", start) or (length + 1)
	return string.sub(line, start, finish - 1), finish, nil
end

function CommandLine.tokenize(line: string): ({ string }, string?)
	local tokens: { string } = {}
	local position = 1
	while true do
		local token, nextPosition, err = CommandLine.nextToken(line, position)
		if err then
			return tokens, err
		end
		if token == nil then
			break
		end
		table.insert(tokens, token)
		position = nextPosition
	end
	return tokens, nil
end

function CommandLine.resolveChoices(arg: ArgDef): { string }
	local choices = arg.choices
	if choices == nil then
		return {}
	end
	local list: any = choices
	if type(choices) == "function" then
		local ok, value = pcall(choices)
		if not ok or type(value) ~= "table" then
			return {}
		end
		list = value
	end
	local out: { string } = {}
	for _, item in ipairs(list) do
		if type(item) == "string" then
			table.insert(out, item)
		end
	end
	return out
end

function CommandLine.isOptional(arg: ArgDef): boolean
	return arg.optional == true or arg.default ~= nil
end

function CommandLine.usage(name: string, args: { ArgDef }): string
	local parts: { string } = { name }
	for _, arg in ipairs(args) do
		local label = arg.name
		local choices = arg.choices
		if arg.type == "choice" and type(choices) == "table" and #choices > 0 and #choices <= MAX_INLINE_CHOICES then
			label = table.concat(choices, "|")
		elseif arg.type == "rest" then
			label ..= "..."
		end
		if CommandLine.isOptional(arg) then
			local suffix = ""
			if arg.default ~= nil and type(arg.default) ~= "table" then
				suffix = "=" .. tostring(arg.default)
			end
			table.insert(parts, `[{label}{suffix}]`)
		else
			table.insert(parts, `<{label}>`)
		end
	end
	return table.concat(parts, " ")
end

local function listChoices(choices: { string }): string
	if #choices <= MAX_LISTED_CHOICES then
		return table.concat(choices, ", ")
	end
	return table.concat(choices, ", ", 1, MAX_LISTED_CHOICES) .. `, ... ({#choices} total)`
end

-- Finds the JSON literal that starts at or after `from`: a balanced {...} or [...] (aware of string
-- contents), or a quoted token holding the JSON text, which spares escaping in shell-like callers.
-- Returns the literal text, the position after it, and a reason on failure ("missing" when the line
-- simply ended).
local function extractJson(line: string, from: number): (string?, number, string?)
	local start = string.find(line, "%S", from)
	if not start then
		return nil, #line + 1, "missing"
	end
	local first = string.sub(line, start, start)
	if first == '"' or first == "'" then
		local token, nextPosition, err = CommandLine.nextToken(line, start)
		return token, nextPosition, err
	end
	if first ~= "{" and first ~= "[" then
		return nil, start, "expected a JSON object or array starting with { or ["
	end
	local depth = 0
	local inString = false
	local index = start
	while index <= #line do
		local char = string.sub(line, index, index)
		if inString then
			if char == "\\" then
				index += 1
			elseif char == '"' then
				inString = false
			end
		elseif char == '"' then
			inString = true
		elseif char == "{" or char == "[" then
			depth += 1
		elseif char == "}" or char == "]" then
			depth -= 1
			if depth == 0 then
				return string.sub(line, start, index), index + 1, nil
			end
		end
		index += 1
	end
	return nil, #line + 1, "unbalanced brackets in JSON"
end

local function checkRange(arg: ArgDef, value: number): string?
	if arg.min ~= nil and value < arg.min then
		return `must be at least {arg.min} (got {value})`
	end
	if arg.max ~= nil and value > arg.max then
		return `must be at most {arg.max} (got {value})`
	end
	return nil
end

-- Converts one token for the token-shaped types. Returns the value or an error reason.
local function convertToken(arg: ArgDef, token: string): (any, string?)
	local argType = arg.type
	if argType == "string" then
		return token, nil
	elseif argType == "number" or argType == "integer" then
		local number = tonumber(token)
		if number == nil or number ~= number or math.abs(number) == math.huge then
			return nil, `expected a number, got '{token}'`
		end
		if argType == "integer" and number % 1 ~= 0 then
			return nil, `expected a whole number, got '{token}'`
		end
		local rangeError = checkRange(arg, number)
		if rangeError then
			return nil, rangeError
		end
		return number, nil
	elseif argType == "boolean" then
		local lower = string.lower(token)
		if TRUE_WORDS[lower] then
			return true, nil
		elseif FALSE_WORDS[lower] then
			return false, nil
		end
		return nil, `expected true or false, got '{token}'`
	elseif argType == "choice" then
		local choices = CommandLine.resolveChoices(arg)
		local lower = string.lower(token)
		for _, choice in ipairs(choices) do
			if string.lower(choice) == lower then
				return choice, nil
			end
		end
		if #choices == 0 then
			return nil, "has no choices available right now"
		end
		return nil, `'{token}' is not one of: {listChoices(choices)}`
	end
	return nil, `unsupported argument type '{argType}'`
end

local function argError(arg: ArgDef, reason: string, usage: string): string
	return `argument '{arg.name}': {reason}\nusage: {usage}`
end

-- Parses the text after the command name against `args`. Returns the arguments by name (absent
-- optional arguments without a default are nil), or nil and a message naming the argument at fault
-- and the usage line.
function CommandLine.parse(argsText: string, args: { ArgDef }, usage: string): (ParsedArgs?, string?)
	local result: ParsedArgs = {}
	local position = 1

	for _, arg in ipairs(args) do
		local value: any = nil
		local present = false

		if arg.type == "rest" then
			local text = string.match(string.sub(argsText, position), "^%s*(.-)%s*$") :: string
			if text ~= "" then
				value = text
				present = true
				position = #argsText + 1
			end
		elseif arg.type == "json" then
			local text, nextPosition, reason = extractJson(argsText, position)
			if text == nil then
				if reason ~= "missing" then
					return nil, argError(arg, reason or "invalid JSON", usage)
				end
			else
				local ok, decoded = pcall(HttpService.JSONDecode, HttpService, text)
				if not ok then
					return nil, argError(arg, `invalid JSON ({tostring(decoded)})`, usage)
				end
				if type(decoded) ~= "table" then
					return nil, argError(arg, "expected a JSON object or array", usage)
				end
				value = decoded
				present = true
				position = nextPosition
			end
		else
			local token, nextPosition, tokenError = CommandLine.nextToken(argsText, position)
			if tokenError then
				return nil, argError(arg, tokenError, usage)
			end
			if token ~= nil then
				local converted, reason = convertToken(arg, token)
				if reason then
					return nil, argError(arg, reason, usage)
				end
				value = converted
				present = true
				position = nextPosition
			end
		end

		if not present then
			if arg.default ~= nil then
				value = if type(arg.default) == "table" then table.clone(arg.default) else arg.default
			elseif not CommandLine.isOptional(arg) then
				return nil, argError(arg, "missing required argument", usage)
			end
		end
		if value ~= nil then
			result[arg.name] = value
		end
	end

	local extra, _, extraError = CommandLine.nextToken(argsText, position)
	if extraError then
		return nil, `{extraError}\nusage: {usage}`
	end
	if extra ~= nil then
		return nil, `unexpected extra argument '{extra}'\nusage: {usage}`
	end
	return result, nil
end

return CommandLine
