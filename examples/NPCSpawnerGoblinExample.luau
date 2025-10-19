--!nocheck
-- Example: spawning a goblin NPC using the NPCSpawner API

local ServerScriptService = game:GetService("ServerScriptService")

local NPCSpawner = require(ServerScriptService.NPCService.NPCSpawner)

local spawnPosition = Vector3.new(0, 5, 0)

local goblinModel, components = NPCSpawner.spawn("Goblin", {
	position = spawnPosition,
})

if goblinModel then
	print("Spawned goblin at", goblinModel:GetPrimaryPartCFrame().Position)
end

if components and components.behavior then
	print("Goblin behavior component ready")
end
