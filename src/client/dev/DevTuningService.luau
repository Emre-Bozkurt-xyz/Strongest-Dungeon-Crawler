--!strict
-- DevTuningService: client-only live tuning overrides for Shared.Config values.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Defaults = require(ReplicatedStorage.Shared.Config)

type Subscriber = {
	prefix: string,
	callback: (string, any) -> (),
}

local Service = {}

local overrides: { [string]: any } = {}
local subscribers: { [number]: Subscriber } = {}
local nextSubId = 0

local function splitPath(path: string): { string }
	local out = {}
	for token in string.gmatch(path, "[^%.]+") do
		table.insert(out, token)
	end
	return out
end

local function pathMatchesPrefix(path: string, prefix: string): boolean
	if prefix == "" then
		return true
	end
	return path == prefix or string.sub(path, 1, #prefix + 1) == (prefix .. ".")
end

local function resolveKey(node: any, wanted: string): string?
	if type(node) ~= "table" then
		return nil
	end
	if node[wanted] ~= nil then
		return wanted
	end
	local target = string.lower(wanted)
	for k in pairs(node) do
		if type(k) == "string" and string.lower(k) == target then
			return k
		end
	end
	return nil
end

local function resolvePathParts(root: any, parts: { string }): { string }?
	local resolved = {}
	local node = root
	for _, part in ipairs(parts) do
		local key = resolveKey(node, part)
		if not key then
			return nil
		end
		table.insert(resolved, key)
		node = node[key]
	end
	return resolved
end

local function readPath(root: any, parts: { string }): any
	local node = root
	for _, key in ipairs(parts) do
		if type(node) ~= "table" then
			return nil
		end
		node = node[key]
		if node == nil then
			return nil
		end
	end
	return node
end

local function deepClone(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in pairs(value) do
		out[k] = deepClone(v)
	end
	return out
end

local function deepMerge(base: any, override: any): any
	if type(base) ~= "table" or type(override) ~= "table" then
		return deepClone(override)
	end
	local out = deepClone(base)
	for k, v in pairs(override) do
		if type(v) == "table" and type(out[k]) == "table" then
			out[k] = deepMerge(out[k], v)
		else
			out[k] = deepClone(v)
		end
	end
	return out
end

local function ensurePath(root: { [string]: any }, parts: { string }): { [string]: any }
	local node = root
	for i = 1, #parts - 1 do
		local key = parts[i]
		if type(node[key]) ~= "table" then
			node[key] = {}
		end
		node = node[key]
	end
	return node
end

local function clearPath(root: { [string]: any }, parts: { string }, idx: number): boolean
	local key = parts[idx]
	if idx == #parts then
		root[key] = nil
	else
		local child = root[key]
		if type(child) ~= "table" then
			return false
		end
		local removed = clearPath(child, parts, idx + 1)
		if not removed then
			return false
		end
		if next(child) == nil then
			root[key] = nil
		end
	end
	return true
end

local function emitChanged(path: string)
	local value = Service.get(path)
	for _, sub in pairs(subscribers) do
		if pathMatchesPrefix(path, sub.prefix) then
			local ok, err = pcall(sub.callback, path, value)
			if not ok then
				warn(string.format("[Tune] subscriber error at '%s': %s", path, tostring(err)))
			end
		end
	end
end

local function parseValue(raw: string): any
	local lower = string.lower(raw)
	if lower == "true" then
		return true
	end
	if lower == "false" then
		return false
	end

	local n = tonumber(raw)
	if n ~= nil then
		return n
	end

	local x, y, z = string.match(raw, "^%s*%(*%s*([%-%d%.]+)%s*,%s*([%-%d%.]+)%s*,%s*([%-%d%.]+)%s*%)?%s*$")
	if x and y and z then
		local xn, yn, zn = tonumber(x), tonumber(y), tonumber(z)
		if xn and yn and zn then
			return Vector3.new(xn, yn, zn)
		end
	end

	return raw
end

local function valueToString(value: any): string
	local t = typeof(value)
	if t == "Vector3" then
		local v = value :: Vector3
		return string.format("Vector3(%.3f, %.3f, %.3f)", v.X, v.Y, v.Z)
	end
	if type(value) == "table" then
		local ok, encoded = pcall(HttpService.JSONEncode, HttpService, value)
		return if ok then encoded else "<table>"
	end
	return tostring(value)
end

local function sortedKeys(node: { [any]: any }): { any }
	local keys = {}
	for k in pairs(node) do
		table.insert(keys, k)
	end
	table.sort(keys, function(a, b)
		local ta = typeof(a)
		local tb = typeof(b)
		if ta == tb then
			if ta == "number" then
				return (a :: number) < (b :: number)
			end
			return tostring(a) < tostring(b)
		end
		return ta < tb
	end)
	return keys
end

local function toLuauLiteral(value: any, depth: number?): string
	local d = depth or 0
	local indent = string.rep("  ", d)
	local nextIndent = string.rep("  ", d + 1)
	local t = typeof(value)
	if t == "nil" then
		return "nil"
	end
	if t == "number" or t == "boolean" then
		return tostring(value)
	end
	if t == "string" then
		return string.format("%q", value)
	end
	if t == "Vector3" then
		local v = value :: Vector3
		return string.format("Vector3.new(%.6g, %.6g, %.6g)", v.X, v.Y, v.Z)
	end
	if type(value) == "table" then
		local keys = sortedKeys(value)
		if #keys == 0 then
			return "{}"
		end
		local lines = { "{\n" }
		for _, key in ipairs(keys) do
			local keyLiteral = if type(key) == "string" and string.match(key, "^[%a_][%w_]*$")
				then key
				else ("[" .. toLuauLiteral(key, d + 1) .. "]")
			local valLiteral = toLuauLiteral(value[key], d + 1)
			table.insert(lines, string.format("%s%s = %s,\n", nextIndent, keyLiteral, valLiteral))
		end
		table.insert(lines, indent .. "}")
		return table.concat(lines)
	end
	return string.format("%q", tostring(value))
end

local function isPathMatch(path: string, filterPrefix: string): boolean
	local p = string.lower(path)
	local f = string.lower(filterPrefix)
	return p == f or string.sub(p, 1, #f + 1) == (f .. ".")
end

local function collectLeafPaths(node: any, prefix: string, out: { string })
	if type(node) ~= "table" then
		if prefix ~= "" then
			table.insert(out, prefix)
		end
		return
	end
	for key, value in pairs(node) do
		if type(key) == "string" then
			local nextPrefix = if prefix == "" then key else (prefix .. "." .. key)
			collectLeafPaths(value, nextPrefix, out)
		end
	end
end

function Service.get(path: string?): any
	if type(path) ~= "string" or path == "" then
		return Defaults
	end
	local rawParts = splitPath(path)
	local parts = resolvePathParts(Defaults, rawParts) or rawParts
	local def = readPath(Defaults, parts)
	local over = readPath(overrides, parts)
	if over ~= nil then
		if type(def) == "table" and type(over) == "table" then
			return deepMerge(def, over)
		end
		return over
	end
	return def
end

-- False (with a warning) when the path names no Config value.
function Service.set(path: string, value: any): boolean
	assert(type(path) == "string" and path ~= "", "DevTuningService.set requires a dotted path")
	local rawParts = splitPath(path)
	local parts = resolvePathParts(Defaults, rawParts)
	if not parts then
		warn(string.format("[Tune] Unknown path '%s' (use 'tune paths' to inspect valid keys)", path))
		return false
	end
	assert(#parts > 0, "DevTuningService.set invalid path")
	local node = ensurePath(overrides, parts)
	node[parts[#parts]] = value
	emitChanged(table.concat(parts, "."))
	return true
end

-- False (with a warning) when the path names no Config value.
function Service.reset(path: string?): boolean
	if path == nil or path == "" then
		overrides = {}
		emitChanged("")
		return true
	end
	local rawParts = splitPath(path)
	local parts = resolvePathParts(Defaults, rawParts)
	if not parts then
		warn(string.format("[Tune] Unknown path '%s' (use 'tune paths' to inspect valid keys)", path))
		return false
	end
	clearPath(overrides, parts, 1)
	emitChanged(table.concat(parts, "."))
	return true
end

function Service.getOverrides(): { [string]: any }
	return overrides
end

-- The override set at `path`, or nil when the path has none (it reads its default).
function Service.getOverride(path: string): any
	local parts = resolvePathParts(Defaults, splitPath(path))
	if not parts then
		return nil
	end
	return readPath(overrides, parts)
end

function Service.listCategories(): { string }
	local categories = {}
	for key in pairs(Defaults) do
		if type(key) == "string" then
			table.insert(categories, key)
		end
	end
	table.sort(categories)
	return categories
end

function Service.listPaths(filterPrefix: string?): { string }
	local paths = {}
	collectLeafPaths(Defaults, "", paths)
	table.sort(paths)
	if type(filterPrefix) ~= "string" or filterPrefix == "" then
		return paths
	end
	local filtered = {}
	for _, path in ipairs(paths) do
		if isPathMatch(path, filterPrefix) then
			table.insert(filtered, path)
		end
	end
	return filtered
end

function Service.subscribe(pathPrefix: string?, callback: (string, any) -> ()): () -> ()
	assert(type(callback) == "function", "DevTuningService.subscribe requires callback")
	nextSubId += 1
	local id = nextSubId
	subscribers[id] = {
		prefix = pathPrefix or "",
		callback = callback,
	}
	return function()
		subscribers[id] = nil
	end
end

-- Runs one tuning command line. Returns whether it succeeded and the lines it reported (also
-- printed, prefixed [Tune]), so a caller such as the console can show them.
function Service.executeCommand(rawCommand: string): (boolean, { string })
	local lines: { string } = {}
	local function say(line: string)
		print("[Tune] " .. line)
		table.insert(lines, line)
	end
	local function complain(line: string)
		warn("[Tune] " .. line)
		table.insert(lines, line)
	end
	if type(rawCommand) ~= "string" or rawCommand == "" then
		complain("Empty command")
		return false, lines
	end
	local message = rawCommand
	if string.sub(message, 1, 5) ~= "/tune" then
		message = "/tune " .. message
	end
	local args = {}
	for token in string.gmatch(message, "%S+") do
		table.insert(args, token)
	end
	local cmd = string.lower(args[2] or "help")
	if cmd == "help" then
		say("tune get <path>")
		say("tune set <path> <value>  (number|bool|Vector3 x,y,z)")
		say("tune setmany <prefix> key=value key2=value2 ...")
		say("tune nudge <path> <delta>")
		say("tune reset [path]")
		say("tune categories")
		say("tune paths [category-or-prefix]")
		say("tune dump")
		say("tune export")
		return true, lines
	end
	if cmd == "categories" or cmd == "cats" then
		local categories = Service.listCategories()
		say(string.format("categories (%d): %s", #categories, table.concat(categories, ", ")))
		return true, lines
	end
	if cmd == "paths" or cmd == "list" then
		local filter = args[3]
		local paths = Service.listPaths(filter)
		say(string.format("paths%s (%d)", if filter then (" for '" .. filter .. "'") else "", #paths))
		for _, path in ipairs(paths) do
			say(string.format("%s = %s", path, valueToString(Service.get(path))))
		end
		return true, lines
	end
	if cmd == "get" then
		local path = args[3]
		if not path then
			complain("Missing path")
			return false, lines
		end
		say(string.format("%s = %s", path, valueToString(Service.get(path))))
		return true, lines
	end
	if cmd == "set" then
		local path = args[3]
		if not path then
			complain("Missing path")
			return false, lines
		end
		local rawValue = table.concat(args, " ", 4)
		if rawValue == "" then
			complain("Missing value")
			return false, lines
		end
		local value = parseValue(rawValue)
		if not Service.set(path, value) then
			complain(string.format("Unknown path '%s'", path))
			return false, lines
		end
		say(string.format("set %s = %s", path, valueToString(value)))
		return true, lines
	end
	if cmd == "setmany" then
		local prefix = args[3]
		if not prefix then
			complain("Missing prefix path")
			return false, lines
		end
		local changed = 0
		for i = 4, #args do
			local pair = args[i]
			local key, rawValue = string.match(pair, "^([^=]+)=(.+)$")
			if not key or not rawValue then
				complain(string.format("Invalid pair '%s' (expected key=value)", pair))
			else
				local value = parseValue(rawValue)
				local fullPath = prefix .. "." .. key
				if Service.set(fullPath, value) then
					changed += 1
				else
					complain(string.format("Unknown path '%s'", fullPath))
				end
			end
		end
		say(string.format("setmany applied %d value(s) under %s", changed, prefix))
		return true, lines
	end
	if cmd == "nudge" then
		local path = args[3]
		local rawDelta = args[4]
		if not path then
			complain("Missing path")
			return false, lines
		end
		if not rawDelta then
			complain("Missing delta")
			return false, lines
		end
		local delta = tonumber(rawDelta)
		if delta == nil then
			complain("Delta must be numeric, e.g. +0.1 or -0.25")
			return false, lines
		end
		local cur = Service.get(path)
		if type(cur) ~= "number" then
			complain(string.format("Cannot nudge non-number at %s (current=%s)", path, valueToString(cur)))
			return false, lines
		end
		local nextValue = (cur :: number) + delta
		Service.set(path, nextValue)
		say(string.format("nudge %s: %s -> %s", path, valueToString(cur), valueToString(nextValue)))
		return true, lines
	end
	if cmd == "reset" then
		local path = args[3]
		if not Service.reset(path) then
			complain(string.format("Unknown path '%s'", tostring(path)))
			return false, lines
		end
		say(if path then string.format("reset %s", path) else "reset all overrides")
		return true, lines
	end
	if cmd == "dump" then
		say(string.format("overrides = %s", valueToString(Service.getOverrides())))
		return true, lines
	end
	if cmd == "export" then
		local currentOverrides = Service.getOverrides()
		local leafPaths = {}
		collectLeafPaths(currentOverrides, "", leafPaths)
		table.sort(leafPaths)
		say("export commands:")
		for _, path in ipairs(leafPaths) do
			local value = Service.get(path)
			local valueRaw: string
			if typeof(value) == "Vector3" then
				local v = value :: Vector3
				valueRaw = string.format("%.6g,%.6g,%.6g", v.X, v.Y, v.Z)
			else
				valueRaw = tostring(value)
			end
			say(string.format("set %s %s", path, valueRaw))
		end
		say("export luau table:")
		say("local tuneOverrides = " .. toLuauLiteral(currentOverrides))
		return true, lines
	end
	complain("Unknown command. Use tune help")
	return false, lines
end

return Service
