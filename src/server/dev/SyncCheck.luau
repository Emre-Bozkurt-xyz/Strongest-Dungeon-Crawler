--!strict
-- Answers "do the scripts in Studio match the files on disk?" Called by hand from plugin-level code
-- (the Studio command bar, or the Studio MCP execute_luau in Edit mode):
--   require(game.ServerScriptService.Server.dev.SyncCheck).run()
-- Nothing here runs unless called. Only plugin-level code can read a script's Source, so a game
-- runtime gets a message back instead of an error.
--
-- The disk half (tools/sync-check) writes a SyncManifest_<nonce> module that Rojo delivers as a new
-- file. A new file arrives even when edits to existing scripts have stopped syncing, so comparing
-- against the manifest still works in that failure mode. The hash is FNV-1a 32 over the UTF-8 bytes
-- after CRLF -> LF, plus the byte length; tools/sync-check/manifest.js computes the same value.

local SyncCheck = {}

local ROOTS = {
	game:GetService("ReplicatedStorage"):FindFirstChild("Shared"),
	game:GetService("ServerScriptService"):FindFirstChild("Server"),
	(game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts") :: Instance?)
		and game:GetService("StarterPlayer").StarterPlayerScripts:FindFirstChild("Client"),
}

local YIELD_EVERY_BYTES = 400000
local MAX_LISTED = 60

local function fnv(source: string): string
	if string.find(source, "\r", 1, true) then
		source = string.gsub(source, "\r\n", "\n")
	end
	local h = 0x811C9DC5
	local len = #source
	local i = 1
	while i <= len do
		local j = math.min(i + 63, len)
		local bytes = { string.byte(source, i, j) }
		for k = 1, #bytes do
			h = bit32.bxor(h, bytes[k])
			-- h * 0x01000193 mod 2^32, split so no intermediate exceeds 2^53
			h = (h * 403 + bit32.lshift(h, 24)) % 4294967296
		end
		i = j + 1
	end
	return string.format("%08x:%d", h, len)
end

local function findManifests(): { ModuleScript }
	local found = {}
	for _, inst in script.Parent:GetChildren() do
		if inst:IsA("ModuleScript") and string.match(inst.Name, "^SyncManifest_%x+$") then
			table.insert(found, inst)
		end
	end
	return found
end

local function list(title: string, items: { string }, out: { string })
	table.sort(items)
	table.insert(out, string.format("%s: %d", title, #items))
	for i = 1, math.min(#items, MAX_LISTED) do
		table.insert(out, "  " .. items[i])
	end
	if #items > MAX_LISTED then
		table.insert(out, string.format("  ... and %d more", #items - MAX_LISTED))
	end
end

export type Result = {
	ok: boolean,
	status: string, -- "match", "mismatch", "no-manifest", "cannot-read-source"
	message: string,
	checked: number,
	manifestAgeSeconds: number?,
	staleManifests: number,
	differ: { string },
	missingInStudio: { string },
	notOnDisk: { string },
}

function SyncCheck.run(): Result
	local result: Result = {
		ok = false,
		status = "",
		message = "",
		checked = 0,
		staleManifests = 0,
		differ = {},
		missingInStudio = {},
		notOnDisk = {},
	}
	local function finish(status: string, message: string): Result
		result.status = status
		result.message = message
		result.ok = status == "match"
		print("[SyncCheck] " .. message)
		return result
	end

	-- Probe Source first: only plugin-level code may read it.
	local readable = pcall(function()
		return script.Source
	end)
	if not readable then
		return finish(
			"cannot-read-source",
			"Script Source is not readable here. Run this from the Studio command bar or execute_luau in Edit mode."
		)
	end

	local manifests = findManifests()
	if #manifests == 0 then
		return finish(
			"no-manifest",
			"No SyncManifest module found. Rojo has not delivered one: either it is not connected to this Studio, or tools/sync-check/run.ps1 was not run."
		)
	end

	local newest, newestAt = nil, -1
	for _, m in manifests do
		local ok, data = pcall(require, m)
		if ok and type(data) == "table" and type(data.generatedAt) == "number" and data.generatedAt > newestAt then
			newest, newestAt = data, data.generatedAt
		end
	end
	if not newest then
		return finish("no-manifest", "SyncManifest modules exist but none could be loaded.")
	end
	result.staleManifests = #manifests - 1
	result.manifestAgeSeconds = os.time() - newestAt

	local expected: { [string]: string } = newest.entries
	local seen: { [string]: boolean } = {}
	local pending = 0
	for _, root in ROOTS do
		if not root then
			continue
		end
		local nodes = root:GetDescendants()
		table.insert(nodes, root)
		for _, inst in nodes do
			if not inst:IsA("LuaSourceContainer") then
				continue
			end
			local path = inst:GetFullName()
			if string.match(inst.Name, "^SyncManifest_%x+$") then
				continue
			end
			if seen[path] then
				table.insert(result.differ, path .. "  (duplicate path in Studio)")
				continue
			end
			seen[path] = true
			result.checked += 1
			local want = expected[path]
			local source = (inst :: any).Source :: string
			if want == nil then
				table.insert(result.notOnDisk, path)
			elseif fnv(source) ~= want then
				table.insert(result.differ, path)
			end
			pending += #source
			if pending >= YIELD_EVERY_BYTES then
				pending = 0
				task.wait()
			end
		end
	end
	for path in expected do
		if not seen[path] then
			table.insert(result.missingInStudio, path)
		end
	end

	local lines = {}
	table.insert(
		lines,
		string.format(
			"manifest age %ds (%d stale manifest module(s) ignored); %d scripts in Studio checked against %d on disk. Packages and ServerPackages are not checked.",
			result.manifestAgeSeconds :: number,
			result.staleManifests,
			result.checked,
			(function()
				local n = 0
				for _ in expected do
					n += 1
				end
				return n
			end)()
		)
	)
	list("source differs from disk", result.differ, lines)
	list("on disk, missing in Studio", result.missingInStudio, lines)
	list("in Studio, no file on disk", result.notOnDisk, lines)
	local bad = #result.differ + #result.missingInStudio + #result.notOnDisk
	return finish(bad == 0 and "match" or "mismatch", (bad == 0 and "MATCH: Studio and disk agree.\n" or "MISMATCH\n") .. table.concat(lines, "\n"))
end

return SyncCheck
