--!strict
-- CommandHelp: the text of `help`, from command descriptors. Shared so the server's `help` and the
-- client's (which lists both realms) read the same.

local CommandRegistry = require(script.Parent.CommandRegistry)

type Descriptor = CommandRegistry.Descriptor
type ArgDescriptor = CommandRegistry.ArgDescriptor

local CommandHelp = {}

local MAX_LISTED_CHOICES = 20

local function describeArg(arg: ArgDescriptor): string
	local notes: { string } = { arg.type }
	if arg.optional then
		table.insert(notes, "optional")
	end
	if arg.default ~= nil and type(arg.default) ~= "table" then
		table.insert(notes, `default {arg.default}`)
	end
	local line = `  {arg.name} ({table.concat(notes, ", ")})`
	local choices = arg.choices
	if choices and #choices > 0 then
		local shown = table.concat(choices, ", ", 1, math.min(#choices, MAX_LISTED_CHOICES))
		line ..= `: {shown}{if #choices > MAX_LISTED_CHOICES then `, ... ({#choices} total)` else ""}`
	end
	return line
end

-- Every command by group, one usage line each.
function CommandHelp.list(descriptors: { Descriptor }): string
	local lines: { string } = {}
	local currentGroup: string? = nil
	for _, descriptor in ipairs(descriptors) do
		if descriptor.group ~= currentGroup then
			currentGroup = descriptor.group
			table.insert(lines, `{descriptor.group}:`)
		end
		table.insert(lines, `  {descriptor.usage}  -  {descriptor.summary}`)
	end
	table.insert(lines, "help <command> shows one command's arguments")
	return table.concat(lines, "\n")
end

-- One command's usage and arguments, or the commands under a first word ("help stage"). Nil when
-- nothing matches.
function CommandHelp.query(descriptors: { Descriptor }, query: string): string?
	local wanted = string.lower((string.gsub(query, "%s+", " ")))
	local related: { Descriptor } = {}
	for _, descriptor in ipairs(descriptors) do
		if descriptor.name == wanted then
			local lines: { string } = { descriptor.usage, descriptor.summary }
			for _, arg in ipairs(descriptor.args) do
				table.insert(lines, describeArg(arg))
			end
			return table.concat(lines, "\n")
		elseif string.sub(descriptor.name, 1, #wanted + 1) == wanted .. " " then
			table.insert(related, descriptor)
		end
	end
	if #related > 0 then
		return CommandHelp.list(related)
	end
	return nil
end

return CommandHelp
