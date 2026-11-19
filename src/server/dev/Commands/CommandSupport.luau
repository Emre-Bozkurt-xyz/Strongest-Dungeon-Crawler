--!strict
-- CommandSupport: what the server command defs share. Game services are loaded on first use rather
-- than at the top of a def file, so a def file never decides startup order and a service that fails
-- to load only breaks the commands that need it.

local CommandRegistry = require(game:GetService("ReplicatedStorage").Shared.Dev.CommandRegistry)

local serverRoot = script:FindFirstAncestor("Server")
assert(serverRoot, "CommandSupport must live under the Server folder")

local CommandSupport = {}

CommandSupport.fail = CommandRegistry.fail

-- Requires a server module by its dotted path below the Server folder ("Services.Registrar").
function CommandSupport.load(path: string): any
	local node: Instance = serverRoot
	for segment in string.gmatch(path, "[^%.]+") do
		local child = node:FindFirstChild(segment)
		if not child then
			error(`server module '{path}' not found (no '{segment}' under {node:GetFullName()})`, 0)
		end
		node = child
	end
	return require(node :: ModuleScript)
end

-- The DevCommands module, for commands that describe the registry itself.
function CommandSupport.devCommands(): any
	return require(script.Parent :: ModuleScript)
end

-- The player a command acts on and their entity id.
function CommandSupport.playerEntity(context: CommandRegistry.Context): (Player, string)
	local player = context.player
	if not player then
		CommandRegistry.fail("this command needs a player and none is in the server")
	end
	local playerId = CommandSupport.load("Services.Registrar").getPlayerId(player)
	if not playerId then
		CommandRegistry.fail(`{player.Name} has no entity id yet (still loading?)`)
	end
	return player, playerId
end

export type LivingEntity = {
	model: Model,
	id: string,
}

-- Living registered entities whose name matches `name`, ignoring case, or the one whose entity id
-- it is -- the id is how a listing (`npcs`, the console) points at one NPC among same-named ones.
function CommandSupport.livingEntities(name: string): { LivingEntity }
	local registrar = CommandSupport.load("Services.Registrar")
	local wanted = string.lower(name)
	local found: { LivingEntity } = {}
	for _, entity in ipairs(registrar.getAllEntities()) do
		local id = registrar.getEntityId(entity)
		local matches = string.lower(entity.Name) == wanted or (id ~= nil and string.lower(id) == wanted)
		if matches and entity:GetAttribute("Dead") ~= true and id then
			table.insert(found, { model = entity, id = id })
		end
	end
	return found
end

function CommandSupport.positionOf(model: Model): Vector3
	local root = model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return model:GetPivot().Position
end

-- `value` in a shape JSON (and so a remote or BindableFunction) carries intact. A table with both
-- positional and named entries -- a character spec item such as { "iron_sword", rarity = "magic" }
-- -- becomes an object whose positional keys are strings ("1"); Vector3s become { x, y, z } lists;
-- anything else that JSON cannot hold becomes its tostring.
function CommandSupport.jsonSafe(value: any): any
	local kind = typeof(value)
	if kind == "string" or kind == "boolean" or kind == "nil" then
		return value
	elseif kind == "number" then
		return if value ~= value or math.abs(value) == math.huge then tostring(value) else value
	elseif kind == "Vector3" then
		return { value.X, value.Y, value.Z }
	elseif kind ~= "table" then
		return tostring(value)
	end
	local count = #value
	local total = 0
	for _ in pairs(value) do
		total += 1
	end
	local out: { [any]: any } = {}
	if total == count then
		for index = 1, count do
			out[index] = CommandSupport.jsonSafe(value[index])
		end
		return out
	end
	for key, child in pairs(value) do
		out[tostring(key)] = CommandSupport.jsonSafe(child)
	end
	return out
end

-- The character's root position, or a failure when the player has no character.
function CommandSupport.characterPosition(player: Player): Vector3
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		CommandRegistry.fail(`{player.Name} has no character`)
	end
	return root.Position
end

return CommandSupport
