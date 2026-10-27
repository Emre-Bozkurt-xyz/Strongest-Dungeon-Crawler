--!strict
-- NPCDeath: what happens when an NPC's health runs out. Until this existed an NPC at 0 health just
-- kept standing (and acting); kills, and everything that hangs off one, had nowhere to start.
--
-- At 0 health an NPC is marked `Dead` (hit queries skip it, and its behaviour already stops on an
-- empty health pool), the death is announced to listeners (character XP), and after a moment it
-- fades and is removed. One spawned with a `respawnDelay` comes back where it first appeared. An
-- `Immortal` NPC -- a training dummy -- refills instead of dying.
--
-- Loot on death is not designed yet and is not here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local TweenService = game:GetService("TweenService")

local StatTypes = require(ReplicatedStorage.Shared.StatTypes)

local Server = ServerScriptService.Server
local StatsManager = require(Server.Stats.StatsManager)
local Registrar = require(Server.Services.Registrar)
local NPCManager = require(script.Parent.NPCManager)
local NPCSpawner = require(script.Parent.NPCSpawner)

-- Seconds a dead NPC stays before fading, and how long the fade takes.
local LINGER_TIME = 1.2
local FADE_TIME = 0.6

local HEALTH = StatTypes.PoolStats.Health

export type DeathListener = (entityId: string, model: Model) -> ()

local NPCDeath = {}

local listeners: { DeathListener } = {}

-- Called once per NPC death, after the killing hit has reached every hit listener.
function NPCDeath.onDeath(listener: DeathListener)
	table.insert(listeners, listener)
end

local function fadeOut(model: Model)
	local info = TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") or descendant:IsA("Decal") then
			TweenService:Create(descendant, info, { Transparency = 1 }):Play()
		end
	end
end

local function scheduleRespawn(model: Model)
	local delay = model:GetAttribute("RespawnDelay")
	local cframe = model:GetAttribute("SpawnCFrame")
	local prefab = model:GetAttribute("CharacterSpecId")
	if type(delay) ~= "number" or typeof(cframe) ~= "CFrame" or type(prefab) ~= "string" then
		return
	end
	task.delay(delay, function()
		NPCSpawner.spawn(prefab, { cframe = cframe, respawnDelay = delay })
	end)
end

local function die(entityId: string, model: Model)
	for _, listener in ipairs(listeners) do
		task.spawn(listener, entityId, model)
	end
	scheduleRespawn(model)
	task.delay(LINGER_TIME, function()
		fadeOut(model)
		task.wait(FADE_TIME)
		NPCManager.unregister(model)
		model:Destroy()
	end)
end

local function onPoolChanged(entityId: string, poolName: string)
	if poolName ~= HEALTH or Registrar.isPlayerEntity(entityId) then
		return
	end
	local model = Registrar.getEntityById(entityId)
	if not model or model:GetAttribute("__isNPC") ~= true or model:GetAttribute("Dead") == true then
		return
	end
	local current = StatsManager.getPoolCurrentValue(entityId, HEALTH)
	if not current or current > 0 then
		return
	end

	if model:GetAttribute("Immortal") == true then
		-- After the emptying hit has resolved, so the refill is not undone by the rest of it.
		task.defer(function()
			local maximum = StatsManager.getPoolMaxValue(entityId, HEALTH)
			if maximum then
				StatsManager.addToPool(entityId, HEALTH, maximum)
			end
		end)
		return
	end

	-- Marked now so nothing hits it again; announced at the end of the frame, by which time the
	-- killing hit has reached CombatService's hit listeners (they run as it resolves).
	model:SetAttribute("Dead", true)
	task.defer(die, entityId, model)
end

function NPCDeath.start()
	StatsManager.onPoolChanged(onPoolChanged)
end

return NPCDeath
