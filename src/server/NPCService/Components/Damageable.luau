--!strict
-- Damageable Component: Interfaces with StatsManager and CombatService for health/damage logic
-- Handles health, shields, defense, etc. via stats system

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Server = game:GetService("ServerScriptService").Server

local StatsManager = require(Server.Stats.StatsManager)
local CombatService = require(script.Parent.Parent.Parent.Services.CombatService)
local NPCManager = require(script.Parent.Parent.NPCManager)
local StatTypes = require(ReplicatedStorage.Shared.StatTypes)

type PlayerStats = StatTypes.PlayerStats
type DamageSource = CombatService.DamageSource

export type DamageableConfig = {
	stats: PlayerStats?,
	configure: ((PlayerStats) -> ())?,
}

local Damageable = {}
Damageable.__index = Damageable

function Damageable.new(entityModel: Model, config: DamageableConfig?): any
	local component = NPCManager.addComponent(entityModel, "Damageable")
	StatsManager.register(entityModel, {
		stats = config and config.stats,
		configure = config and config.configure,
		skipSync = true,
	})
	component:SetAttribute("lastDamageAt", 0)
	component:SetAttribute("lastHealedAt", 0)

	return setmetatable({
		model = entityModel,
		component = component,
	}, Damageable)
end

function Damageable.get(entityModel: Model): any?
	if not NPCManager.hasComponent(entityModel, "Damageable") then
		return nil
	end
	local component = NPCManager.getComponent(entityModel, "Damageable")

	return setmetatable({
		model = entityModel,
		component = component,
	}, Damageable)
end

function Damageable:getHealth(): number
	return StatsManager.getPoolCurrentValue(self.model, StatTypes.PoolStats.Health) or 0
end

function Damageable:getMaxHealth(): number
	return StatsManager.getPoolMaxValue(self.model, StatTypes.PoolStats.Health) or 0
end

function Damageable:applyDamage(amount: number, source: DamageSource?, damageType: string?)
	if self.component then
		self.component:SetAttribute("lastDamageAt", os.clock())
	end
	return CombatService.applyDamageDetailed(self.model, amount, source, { kind = damageType })
end

function Damageable:heal(amount: number)
	if self.component then
		self.component:SetAttribute("lastHealedAt", os.clock())
	end
	return StatsManager.addToPool(self.model, StatTypes.PoolStats.Health, amount)
end

function Damageable:isAlive(): boolean
	return self:getHealth() > 0
end

return Damageable
