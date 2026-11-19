--!strict
-- Autocomplete for the command line, from the command descriptors alone: command names first, then
-- the current argument's choices (or true/false), and a hint naming the argument being typed. Pure
-- functions of the text and the descriptors, so the command line can call it on every keystroke.
--
-- The cursor is taken to be at the end of the line, which is where typing happens; completing in the
-- middle of a line is not worth the bookkeeping for a dev tool.

local CommandLine = require(game:GetService("ReplicatedStorage").Shared.Dev.CommandLine)

local Autocomplete = {}

export type Suggestion = {
	-- What the list shows.
	label: string,
	-- The whole line after accepting it.
	line: string,
	-- "command" or "value".
	kind: string,
	-- Shown beside a command name.
	detail: string?,
}

export type Analysis = {
	-- The command the line starts with, when it names one completely.
	descriptor: any?,
	-- Which of its arguments is being typed (1-based), or nil before the name is complete.
	argIndex: number?,
	suggestions: { Suggestion },
}

local MAX_SUGGESTIONS = 8

-- Splits the line into tokens with quotes respected. `open` is true when the line does not end in
-- whitespace, i.e. the last token is still being typed. A line whose last quote is unclosed counts its
-- quoted text as the open token.
local function tokens(line: string): ({ string }, boolean)
	local list, err = CommandLine.tokenize(line)
	if err then
		local quote = string.match(line, "^.*()[\"']")
		if quote then
			local rest = string.sub(line, quote + 1)
			local before = CommandLine.tokenize(string.sub(line, 1, quote - 1))
			table.insert(before, rest)
			return before, true
		end
	end
	return list, line ~= "" and not string.match(line, "%s$")
end

local function quoteIfNeeded(value: string): string
	if string.find(value, "%s") then
		return '"' .. value .. '"'
	end
	return value
end

-- Matches by prefix first, then anywhere in the word, case-insensitively, keeping list order within
-- each group.
local function rank(candidates: { string }, typed: string): { string }
	local needle = string.lower(typed)
	local prefix: { string } = {}
	local inside: { string } = {}
	for _, candidate in ipairs(candidates) do
		local lower = string.lower(candidate)
		if needle == "" or string.sub(lower, 1, #needle) == needle then
			table.insert(prefix, candidate)
		elseif string.find(lower, needle, 1, true) then
			table.insert(inside, candidate)
		end
	end
	for _, candidate in ipairs(inside) do
		table.insert(prefix, candidate)
	end
	return prefix
end

-- The longest command name made of the first words of the line, and how many tokens it spans.
local function matchCommand(list: { string }, descriptors: { any }): (any?, number)
	local best: any? = nil
	local bestWords = 0
	for _, descriptor in ipairs(descriptors) do
		local words = string.split(descriptor.name, " ")
		if #words <= #list and #words > bestWords then
			local same = true
			for index, word in ipairs(words) do
				if string.lower(list[index]) ~= word then
					same = false
					break
				end
			end
			if same then
				best, bestWords = descriptor, #words
			end
		end
	end
	return best, bestWords
end

local function commandSuggestions(typed: string, descriptors: { any }): { Suggestion }
	local names: { string } = {}
	local byName: { [string]: any } = {}
	for _, descriptor in ipairs(descriptors) do
		table.insert(names, descriptor.name)
		byName[descriptor.name] = descriptor
	end
	local out: { Suggestion } = {}
	for _, name in ipairs(rank(names, typed)) do
		if string.lower(name) ~= string.lower(typed) or #(byName[name].args or {}) > 0 then
			table.insert(out, { label = name, line = name .. " ", kind = "command", detail = byName[name].summary })
		end
		if #out >= MAX_SUGGESTIONS then
			break
		end
	end
	return out
end

function Autocomplete.analyze(line: string, descriptors: { any }): Analysis
	local list, open = tokens(line)
	local typedLine = string.lower((string.gsub(line, "^%s+", "")))
	-- An empty line offers nothing: the whole registry would only cover the result above it.
	if typedLine == "" then
		return { descriptor = nil, argIndex = nil, suggestions = {} }
	end
	local descriptor, nameWords = matchCommand(list, descriptors)

	-- Still on the name: either nothing matches completely yet, or the name's last word is the open
	-- token (so "tp" may still become "tp start").
	if not descriptor or (open and nameWords == #list) then
		local analysis: Analysis = {
			descriptor = descriptor,
			argIndex = nil,
			suggestions = commandSuggestions(typedLine, descriptors),
		}
		return analysis
	end

	local argTokens = #list - nameWords
	local argIndex = if open then argTokens else argTokens + 1
	local partial = if open then list[#list] else ""
	local prefixTokens = table.move(list, 1, #list - (if open then 1 else 0), 1, {})
	local head = table.concat(
		(function()
			local quoted = {}
			for index, token in ipairs(prefixTokens) do
				quoted[index] = if index <= nameWords then token else quoteIfNeeded(token)
			end
			return quoted
		end)(),
		" "
	)

	local suggestions: { Suggestion } = {}
	local arg = descriptor.args and descriptor.args[argIndex]
	if arg then
		local values: { string } = {}
		if arg.type == "choice" then
			values = arg.choices or {}
		elseif arg.type == "boolean" then
			values = { "true", "false" }
		end
		for _, value in ipairs(rank(values, partial)) do
			if value ~= partial then
				table.insert(suggestions, {
					label = value,
					line = (if head == "" then "" else head .. " ") .. quoteIfNeeded(value) .. " ",
					kind = "value",
				})
			end
			if #suggestions >= MAX_SUGGESTIONS then
				break
			end
		end
	end

	-- Longer commands sharing this name ("tp" and "tp start") stay on offer for the first argument.
	if argIndex == 1 then
		for _, extra in ipairs(commandSuggestions(typedLine, descriptors)) do
			if extra.label ~= descriptor.name and #suggestions < MAX_SUGGESTIONS then
				table.insert(suggestions, extra)
			end
		end
	end

	return { descriptor = descriptor, argIndex = argIndex, suggestions = suggestions }
end

-- "<name: type>" for one argument, with its range or default.
function Autocomplete.describeArg(arg: any): string
	local parts = { arg.name, ": ", arg.type }
	if arg.min ~= nil and arg.max ~= nil then
		table.insert(parts, ` {arg.min}–{arg.max}`)
	elseif arg.min ~= nil then
		table.insert(parts, ` ≥{arg.min}`)
	elseif arg.max ~= nil then
		table.insert(parts, ` ≤{arg.max}`)
	end
	if arg.default ~= nil and type(arg.default) ~= "table" then
		table.insert(parts, ` = {tostring(arg.default)}`)
	end
	local text = table.concat(parts)
	return if arg.optional then `[{text}]` else `<{text}>`
end

return Autocomplete
