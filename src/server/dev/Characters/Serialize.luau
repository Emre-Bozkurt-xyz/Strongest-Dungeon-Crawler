--!strict
-- A spec as readable Luau source (`return { ... }`), so a captured character can be pasted into a
-- preset file. Top-level fields come in the order Types documents them; nested keys sort, after any
-- positional entries. Short tables of plain values stay on one line.

local Serialize = {}

local FIELD_ORDER = {
	"extends",
	"level",
	"xp",
	"attributes",
	"mastery",
	"attuned",
	"skills",
	"bar",
	"activeSet",
	"equipment",
	"bag",
	"capacity",
	"shapes",
	"infusion",
	"passives",
	"pools",
	"stats",
}

local INLINE_WIDTH = 72

local RESERVED: { [string]: boolean } = {}
for _, word in
	ipairs({
		"and", "break", "do", "else", "elseif", "end", "false", "for", "function", "if", "in",
		"local", "nil", "not", "or", "repeat", "return", "then", "true", "until", "while", "continue",
	})
do
	RESERVED[word] = true
end

local function keyText(key: any): string
	if type(key) == "string" and string.match(key, "^[%a_][%w_]*$") and not RESERVED[key] then
		return key
	end
	if type(key) == "string" then
		return `[{string.format("%q", key)}]`
	end
	return `[{tostring(key)}]`
end

local function numberText(value: number): string
	if value == math.floor(value) and math.abs(value) < 2 ^ 53 then
		return string.format("%d", value)
	end
	return tostring(value)
end

local function sortedKeys(value: { [any]: any }, skipArray: number, order: { string }?): { any }
	local keys = {}
	for key in pairs(value) do
		if not (type(key) == "number" and key >= 1 and key <= skipArray and key == math.floor(key)) then
			table.insert(keys, key)
		end
	end
	local rank: { [any]: number } = {}
	for index, name in ipairs(order or {}) do
		rank[name] = index
	end
	table.sort(keys, function(a, b)
		local ra, rb = rank[a], rank[b]
		if ra or rb then
			return (ra or math.huge) < (rb or math.huge)
		end
		if type(a) ~= type(b) then
			return type(a) == "number"
		end
		return a < b
	end)
	return keys
end

local function valueText(value: any, depth: number, order: { string }?, forceMultiline: boolean?): string
	local kind = type(value)
	if kind == "string" then
		return string.format("%q", value)
	elseif kind == "number" then
		return numberText(value)
	elseif kind == "boolean" then
		return tostring(value)
	elseif kind ~= "table" then
		return "nil"
	end
	if next(value) == nil then
		return "{}"
	end

	local parts: { string } = {}
	local count = #value
	for index = 1, count do
		table.insert(parts, valueText(value[index], depth + 1, nil))
	end
	for _, key in ipairs(sortedKeys(value, count, order)) do
		table.insert(parts, `{keyText(key)} = {valueText(value[key], depth + 1, nil)}`)
	end

	if not forceMultiline then
		local inline = `\{ {table.concat(parts, ", ")} }`
		if #inline + depth * 4 <= INLINE_WIDTH and not string.find(inline, "\n") then
			return inline
		end
	end
	local indent = string.rep("\t", depth + 1)
	return `\{\n{indent}{table.concat(parts, `,\n{indent}`)},\n{string.rep("\t", depth)}}`
end

function Serialize.toLuau(spec: { [string]: any }): string
	return `return {valueText(spec, 0, FIELD_ORDER, true)}\n`
end

return Serialize
