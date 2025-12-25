--!strict
-- Damageable Component: Interfaces with StatsManager and CombatService for health/damage logic
-- Handles health, shields, defense, etc. via stats system

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Server = game:GetService("ServerScriptService").Server

local StatsManager = require(Server.Stats.StatsManager)
local CombatService = require(script.Parent.Parent.Parent.Services.CombatService)
local NPCManager = require(script.Parent.Parent.NPCManager)
local StatTypes = require(ReplicatedStorage.Shared.StatTypes)
local Registrar = require(Server.Services.Registrar)

type PlayerStats = StatTypes.PlayerStats
type DamageSource = CombatService.DamageSource

export type DamageableConfig = {
	stats: PlayerStats?,
	configure: ((PlayerStats) -> ())?,
}

local Damageable = {}
Damageable.__index = Damageable

-- Helper to get entityId from model
local function getEntityId(model: Model): string?
	return Registrar.getEntityId(model)
end

function Damageable.new(entityModel: Model, config: DamageableConfig?): any
	local component = NPCManager.addComponent(entityModel, "Damageable")

	-- Get entityId for StatsManager (model must be registered by NPCManager first)
	local entityId = getEntityId(entityModel)
	if not entityId then
		warn(`Damageable.new: Entity {entityModel.Name} has no entityId - was NPCManager.register called first?`)
		return nil
	end

	StatsManager.register(entityId, {
		stats = config and config.stats,
		configure = config and config.configure,
		skipSync = true,
	})
	component:SetAttribute("lastDamageAt", 0)
	component:SetAttribute("lastHealedAt", 0)

	return setmetatable({
		model = entityModel,
		entityId = entityId,
		component = component,
	}, Damageable)
end

function Damageable.get(entityModel: Model): any?
	if not NPCManager.hasComponent(entityModel, "Damageable") then
		return nil
	end
	local component = NPCManager.getComponent(entityModel, "Damageable")

	local entityId = getEntityId(entityModel)
	if not entityId then
		return nil
	end

	return setmetatable({
		model = entityModel,
		entityId = entityId,
		component = component,
	}, Damageable)
end

function Damageable:getHealth(): number
	return StatsManager.getPoolCurrentValue(self.entityId, StatTypes.PoolStats.Health) or 0
end

function Damageable:getMaxHealth(): number
	return StatsManager.getPoolMaxValue(self.entityId, StatTypes.PoolStats.Health) or 0
end

function Damageable:heal(amount: number)
	if self.component then
		self.component:SetAttribute("lastHealedAt", os.clock())
	end
	return StatsManager.addToPool(self.entityId, StatTypes.PoolStats.Health, amount)
end

function Damageable:isAlive(): boolean
	return self:getHealth() > 0
end

return Damageable
