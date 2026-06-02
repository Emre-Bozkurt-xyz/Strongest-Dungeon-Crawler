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

function Service.set(path: string, value: any)
	assert(type(path) == "string" and path ~= "", "DevTuningService.set requires a dotted path")
	local rawParts = splitPath(path)
	local parts = resolvePathParts(Defaults, rawParts)
	if not parts then
		warn(string.format("[Tune] Unknown path '%s' (use '/tune paths' to inspect valid keys)", path))
		return
	end
	assert(#parts > 0, "DevTuningService.set invalid path")
	local node = ensurePath(overrides, parts)
	node[parts[#parts]] = value
	emitChanged(table.concat(parts, "."))
end

function Service.reset(path: string?)
	if path == nil or path == "" then
		overrides = {}
		emitChanged("")
		return
	end
	local rawParts = splitPath(path)
	local parts = resolvePathParts(Defaults, rawParts)
	if not parts then
		warn(string.format("[Tune] Unknown path '%s' (use '/tune paths' to inspect valid keys)", path))
		return
	end
	clearPath(overrides, parts, 1)
	emitChanged(table.concat(parts, "."))
end

function Service.getOverrides(): { [string]: any }
	return overrides
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

function Service.executeCommand(rawCommand: string): boolean
	if type(rawCommand) ~= "string" or rawCommand == "" then
		warn("[Tune] Empty command")
		return false
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
		print("[Tune] /tune get <path>")
		print("[Tune] /tune set <path> <value>  (number|bool|Vector3 x,y,z)")
		print("[Tune] /tune setmany <prefix> key=value key2=value2 ...")
		print("[Tune] /tune nudge <path> <delta>")
		print("[Tune] /tune reset [path]")
		print("[Tune] /tune categories")
		print("[Tune] /tune paths [category-or-prefix]")
		print("[Tune] /tune dump")
		print("[Tune] /tune export")
		return true
	end
	if cmd == "categories" or cmd == "cats" then
		local categories = Service.listCategories()
		print(string.format("[Tune] categories (%d): %s", #categories, table.concat(categories, ", ")))
		return true
	end
	if cmd == "paths" or cmd == "list" then
		local filter = args[3]
		local paths = Service.listPaths(filter)
		print(
			string.format(
				"[Tune] paths%s (%d)",
				if filter then (" for '" .. filter .. "'") else "",
				#paths
			)
		)
		for _, path in ipairs(paths) do
			print(string.format("[Tune] %s = %s", path, valueToString(Service.get(path))))
		end
		return true
	end
	if cmd == "get" then
		local path = args[3]
		if not path then
			warn("[Tune] Missing path")
			return false
		end
		print(string.format("[Tune] %s = %s", path, valueToString(Service.get(path))))
		return true
	end
	if cmd == "set" then
		local path = args[3]
		if not path then
			warn("[Tune] Missing path")
			return false
		end
		local rawValue = table.concat(args, " ", 4)
		if rawValue == "" then
			warn("[Tune] Missing value")
			return false
		end
		local value = parseValue(rawValue)
		Service.set(path, value)
		print(string.format("[Tune] set %s = %s", path, valueToString(value)))
		return true
	end
	if cmd == "setmany" then
		local prefix = args[3]
		if not prefix then
			warn("[Tune] Missing prefix path")
			return false
		end
		local changed = 0
		for i = 4, #args do
			local pair = args[i]
			local key, rawValue = string.match(pair, "^([^=]+)=(.+)$")
			if not key or not rawValue then
				warn(string.format("[Tune] Invalid pair '%s' (expected key=value)", pair))
			else
				local value = parseValue(rawValue)
				local fullPath = prefix .. "." .. key
				Service.set(fullPath, value)
				changed += 1
			end
		end
		print(string.format("[Tune] setmany applied %d value(s) under %s", changed, prefix))
		return true
	end
	if cmd == "nudge" then
		local path = args[3]
		local rawDelta = args[4]
		if not path then
			warn("[Tune] Missing path")
			return false
		end
		if not rawDelta then
			warn("[Tune] Missing delta")
			return false
		end
		local delta = tonumber(rawDelta)
		if delta == nil then
			warn("[Tune] Delta must be numeric, e.g. +0.1 or -0.25")
			return false
		end
		local cur = Service.get(path)
		if type(cur) ~= "number" then
			warn(string.format("[Tune] Cannot nudge non-number at %s (current=%s)", path, valueToString(cur)))
			return false
		end
		local nextValue = (cur :: number) + delta
		Service.set(path, nextValue)
		print(string.format("[Tune] nudge %s: %s -> %s", path, valueToString(cur), valueToString(nextValue)))
		return true
	end
	if cmd == "reset" then
		local path = args[3]
		Service.reset(path)
		print(if path then string.format("[Tune] reset %s", path) else "[Tune] reset all overrides")
		return true
	end
	if cmd == "dump" then
		print(string.format("[Tune] overrides = %s", valueToString(Service.getOverrides())))
		return true
	end
	if cmd == "export" then
		local currentOverrides = Service.getOverrides()
		local leafPaths = {}
		collectLeafPaths(currentOverrides, "", leafPaths)
		table.sort(leafPaths)
		print("[Tune] export commands:")
		for _, path in ipairs(leafPaths) do
			local value = Service.get(path)
			local valueRaw: string
			if typeof(value) == "Vector3" then
				local v = value :: Vector3
				valueRaw = string.format("%.6g,%.6g,%.6g", v.X, v.Y, v.Z)
			else
				valueRaw = tostring(value)
			end
			print(string.format("[Tune] set %s %s", path, valueRaw))
		end
		print("[Tune] export luau table:")
		print("local tuneOverrides = " .. toLuauLiteral(currentOverrides))
		return true
	end
	warn("[Tune] Unknown command. Use /tune help")
	return false
end

return Service
