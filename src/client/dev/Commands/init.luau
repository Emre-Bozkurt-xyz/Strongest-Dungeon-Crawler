--!strict
-- DevCommandsClient: the client's dev command entry point. Commands that only make sense on the
-- client (tuning, client debug flags) run from the local registry; everything else is forwarded to the
-- server through DevRemote, which authorizes it. A command name registered here shadows a server
-- command of the same name, so a client command is always what runs for that name.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CommandRegistry = require(ReplicatedStorage.Shared.Dev.CommandRegistry)
local DevAccess = require(ReplicatedStorage.Shared.Dev.DevAccess)

export type CommandDef = CommandRegistry.CommandDef
export type Descriptor = CommandRegistry.Descriptor
export type Result = CommandRegistry.Result

export type LogEntry = {
	text: string,
	result: Result,
	time: number,
}

local LOG_LIMIT = 200
-- How long a request waits for the server to create DevRemote before giving up.
local REMOTE_WAIT_SECONDS = 5

local DevCommandsClient = {}

local registry = CommandRegistry.new("client")
local started = false
local log: { LogEntry } = {}
local listeners: { [number]: (LogEntry) -> () } = {}
local nextListenerId = 0
local serverDescriptors: { Descriptor }? = nil

function DevCommandsClient.register(def: CommandDef)
	registry:register(def)
end

local function failure(message: string): Result
	return { ok = false, message = message }
end

local function getRemote(): RemoteFunction?
	local remote = ReplicatedStorage:FindFirstChild("DevRemote") or ReplicatedStorage:WaitForChild("DevRemote", REMOTE_WAIT_SECONDS)
	if remote and remote:IsA("RemoteFunction") then
		return remote
	end
	return nil
end

-- Sends one request to the server and returns its Result, or a failure Result when the server cannot
-- be reached. Yields.
local function requestServer(action: string, payload: string?): Result
	local remote = getRemote()
	if not remote then
		return failure("the server has no dev commands (DevRemote is missing)")
	end
	local ok, response = pcall(function()
		return remote:InvokeServer(action, payload)
	end)
	if not ok then
		return failure(`server request failed: {tostring(response)}`)
	end
	if type(response) ~= "table" or type(response.ok) ~= "boolean" or type(response.message) ~= "string" then
		return failure("the server sent a malformed reply")
	end
	return response
end

local function execute(text: string): Result
	if type(text) ~= "string" then
		return failure("a command is a string")
	end
	if registry:find(text) then
		return registry:run(text, { player = Players.LocalPlayer, realm = "client" })
	end
	if string.match(text, "^%s*$") then
		return failure("empty command")
	end
	local result = requestServer("run", text)
	-- The server only knows its own names; a typo of a client command should still be suggested.
	if not result.ok and string.sub(result.message, 1, 16) == "unknown command " then
		local suggestions = registry:suggest(text)
		local serverPart = string.match(result.message, "Did you mean: (.-)%?$")
		if serverPart then
			for name in string.gmatch(serverPart, "[^,]+") do
				local trimmed = string.match(name, "^%s*(.-)%s*$") :: string
				if not table.find(suggestions, trimmed) then
					table.insert(suggestions, trimmed)
				end
			end
		end
		local typed = string.match(result.message, "^(unknown command '.-')") or "unknown command"
		local message = typed
		if #suggestions > 0 then
			message ..= `. Did you mean: {table.concat(suggestions, ", ", 1, math.min(#suggestions, 3))}?`
		end
		return { ok = false, message = message }
	end
	return result
end

local function appendLog(entry: LogEntry)
	table.insert(log, entry)
	if #log > LOG_LIMIT then
		table.remove(log, 1)
	end
	for _, callback in pairs(listeners) do
		task.spawn(callback, entry)
	end
end

-- Runs a command line on whichever realm owns it. Yields when it goes to the server, so call it from
-- a coroutine or a UI callback.
function DevCommandsClient.run(text: string): Result
	local result = execute(text)
	appendLog({ text = text, result = result, time = os.time() })
	return result
end

-- Runs a command line without adding it to the log: for UIs that read lists (`scenario list`,
-- `npcs`) to show them, which would otherwise bury what the developer ran. Yields like `run`.
function DevCommandsClient.query(text: string): Result
	return execute(text)
end

-- Client and server commands together, by group then name; a client command hides a server command
-- of the same name. The server's list is fetched on first use and kept; a failed fetch is not kept,
-- so the next call retries.
function DevCommandsClient.describe(): { Descriptor }
	if serverDescriptors == nil then
		local response = requestServer("describe", nil)
		if response.ok and type(response.data) == "table" then
			serverDescriptors = response.data
		end
	end

	local clientNames: { [string]: boolean } = {}
	local merged: { Descriptor } = {}
	for _, descriptor in ipairs(registry:describe()) do
		clientNames[descriptor.name] = true
		table.insert(merged, descriptor)
	end
	for _, descriptor in ipairs(serverDescriptors or {}) do
		if not clientNames[descriptor.name] then
			table.insert(merged, descriptor)
		end
	end
	table.sort(merged, function(a, b)
		if a.group ~= b.group then
			return a.group < b.group
		end
		return a.name < b.name
	end)
	return merged
end

-- Forgets the cached server list and fetches it again (choice lists follow live data).
function DevCommandsClient.refresh(): { Descriptor }
	serverDescriptors = nil
	return DevCommandsClient.describe()
end

function DevCommandsClient.getLog(): { LogEntry }
	return table.clone(log)
end

function DevCommandsClient.clearLog()
	table.clear(log)
end

-- Calls `callback` for every entry added to the log. Returns the function that stops it.
function DevCommandsClient.onLog(callback: (LogEntry) -> ()): () -> ()
	nextListenerId += 1
	local id = nextListenerId
	listeners[id] = callback
	return function()
		listeners[id] = nil
	end
end

local function loadDefs()
	local folder = script:FindFirstChild("Defs")
	if not folder then
		warn("[DevCommandsClient] no Defs folder; no client commands loaded")
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
			warn(`[DevCommandsClient] could not load {module.Name}: {tostring(defs)}`)
			continue
		end
		for _, def in ipairs(defs) do
			local registered, err = pcall(DevCommandsClient.register, def)
			if not registered then
				warn(`[DevCommandsClient] {module.Name}: {tostring(err)}`)
			end
		end
	end
end

-- ReplicatedStorage.DevClient, created by this client only, is the automation entry point for the
-- client realm: Studio command-bar and MCP code run with their own module cache, so they cannot
-- reach this module, but they share the DataModel. Invoke(text) runs a line exactly as the console
-- would and returns its Result.
local function createEntryPoint()
	local existing = ReplicatedStorage:FindFirstChild("DevClient")
	if existing then
		existing:Destroy()
	end
	local entry = Instance.new("BindableFunction")
	entry.Name = "DevClient"
	entry.OnInvoke = function(text: any): Result
		if type(text) ~= "string" then
			return failure("DevClient:Invoke expects the command text as a string")
		end
		return DevCommandsClient.run(text)
	end
	entry.Parent = ReplicatedStorage
end

-- Does nothing when dev tooling is not enabled for this session.
function DevCommandsClient.start()
	if started or not DevAccess.isEnabled() then
		return
	end
	started = true
	loadDefs()
	createEntryPoint()
end

return DevCommandsClient
