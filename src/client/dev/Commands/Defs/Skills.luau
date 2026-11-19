--!strict
-- The client's own view of skill timing: the cooldowns it predicts locally, which is what gates
-- casting (the server's cooldowns are not mirrored for that).

local devFolder = script:FindFirstAncestor("dev")
assert(devFolder and devFolder.Parent, "client command defs must live under the dev folder")
local skillsFramework = (devFolder.Parent :: Instance):FindFirstChild("SkillsFramework") :: Instance
local CooldownClient = require(skillsFramework:FindFirstChild("CooldownClient") :: ModuleScript)

return {
	{
		name = "cooldowns",
		group = "Debug",
		summary = "List the cooldowns this client is counting down",
		run = function()
			local list = CooldownClient.iterate()
			table.sort(list, function(a, b)
				return a.key < b.key
			end)
			local lines: { string } = {}
			local data = {}
			for _, entry in ipairs(list) do
				local remaining = math.floor(entry.remaining * 100 + 0.5) / 100
				table.insert(lines, `{entry.key} {remaining}s`)
				table.insert(data, { key = entry.key, remaining = remaining })
			end
			return {
				message = if #lines > 0 then table.concat(lines, "\n") else "no cooldowns",
				data = { cooldowns = data },
			}
		end,
	},
}
