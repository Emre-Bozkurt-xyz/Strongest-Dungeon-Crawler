--!strict
-- DevCommands: the server's dev command registry and its two entry points.
--
-- ServerStorage.Dev is a BindableFunction because the Studio command bar and MCP scripts run with
-- their own module cache and `_G`, so they cannot call this module directly; an instance is the only
-- thing they share with the game. It is server-only, hence trusted. ReplicatedStorage.DevRemote is
-- the client console's path and authorizes every request itself. Both live here rather than in the
-- production networking layer so dev tooling can be removed without touching shared channels.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local CommandRegistry = require(ReplicatedStorage.Shared.Dev.CommandRegistry)
local DevAccess = require(ReplicatedStorage.Shared.Dev.DevAccess)

export type CommandDef = CommandRegistry.CommandDef
export type Descriptor = CommandRegistry.Descriptor
export type Result = CommandRegistry.Result

export type HistoryEntry = {
	time: number,
	player: Player?,
	text: string,
	result: Result,
}

local HISTORY_LIMIT = 100
local MAX_TEXT_LENGTH = 2000

local DevCommands = {}

local registry = CommandRegistry.new("server")
local history: { HistoryEntry } = {}
local started = false

function DevCommands.register(def: CommandDef)
	registry:register(def)
end

function DevCommands.run(text: string, player: Player?): Result
	local result = registry:run(text, { player = player, realm = "server" })
	table.insert(history, { time = os.time(), player = player, text = text, result = result })
	if #history > HISTORY_LIMIT then
		table.remove(history, 1)
	end
	return result
end

function DevCommands.describe(): { Descriptor }
	return registry:describe()
end

-- Oldest first.
function DevCommands.history(): { HistoryEntry }
	return table.clone(history)
end

-- Data crosses the remote as-is, so anything that is not plain JSON-able (Instances, functions,
-- Vector3s) is dropped rather than failing the whole reply.
local function remoteSafe(result: Result): Result
	local data = result.data
	if data ~= nil and not pcall(HttpService.JSONEncode, HttpService, data) then
		data = nil
	end
	return { ok = result.ok, message = result.message, data = data }
end

local function refused(message: string): Result
	return { ok = false, message = message }
end

local function handleRemote(player: Player, action: any, payload: any): Result
	if not DevAccess.canUse(player) then
		return refused("dev commands are not available to you")
	end
	if action == "describe" then
		return { ok = true, message = "", data = DevCommands.describe() }
	elseif action == "run" then
		if type(payload) ~= "string" then
			return refused("run expects the command text as a string")
		end
		if #payload > MAX_TEXT_LENGTH then
			return refused(`command is too long (limit {MAX_TEXT_LENGTH} characters)`)
		end
		return remoteSafe(DevCommands.run(payload, player))
	end
	return refused("unknown request")
end

local function replaceInstance(className: string, name: string, parent: Instance): Instance
	local existing = parent:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end
	local instance = Instance.new(className)
	instance.Name = name
	return instance
end

local function createEntryPoints()
	local entry = replaceInstance("BindableFunction", "Dev", ServerStorage) :: BindableFunction
	entry.OnInvoke = function(text: any, player: any): Result
		if type(text) ~= "string" then
			return refused("Dev:Invoke expects the command text as a string")
		end
		local target: Player? = nil
		if player == nil then
			target = Players:GetPlayers()[1]
		elseif typeof(player) == "Instance" and player:IsA("Player") then
			target = player
		else
			return refused("Dev:Invoke expects a Player or nil as the second argument")
		end
		return DevCommands.run(text, target)
	end
	entry.Parent = ServerStorage

	local remote = replaceInstance("RemoteFunction", "DevRemote", ReplicatedStorage) :: RemoteFunction
	remote.OnServerInvoke = function(player: Player, action: any, payload: any): Result
		local ok, result = pcall(handleRemote, player, action, payload)
		if not ok then
			return refused(tostring(result))
		end
		return result
	end
	remote.Parent = ReplicatedStorage
end

-- Every ModuleScript under Defs returns a list of command defs.
local function loadDefs()
	local folder = script:FindFirstChild("Defs")
	if not folder then
		warn("[DevCommands] no Defs folder; no commands loaded")
		return
	end
	local modules: { ModuleScript } = {}
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("ModuleScript") then
			table.insert(modules, child)
		end
	end
	table.sort(modules, function(a, b)
		return a.Name < b.Name
	end)

	for _, module in ipairs(modules) do
		local ok, defs = pcall(require, module)
		if not ok or type(defs) ~= "table" then
			warn(`[DevCommands] could not load {module.Name}: {tostring(defs)}`)
			continue
		end
		for _, def in ipairs(defs) do
			local registered, err = pcall(DevCommands.register, def)
			if not registered then
				warn(`[DevCommands] {module.Name}: {tostring(err)}`)
			end
		end
	end
end

-- Does nothing when dev tooling is not enabled for this session.
function DevCommands.start()
	if started or not DevAccess.isEnabled() then
		return
	end
	started = true
	loadDefs()
	createEntryPoints()
end

return DevCommands
