local Server = game:GetService("ServerScriptService").Server

local BaseComboSkill = require(script.Parent.BaseComboSkill)
local StatsManager = require(Server.Stats.StatsManager)
local HitboxService = require(script.Parent.Parent.HitboxService)
local CombatService = require(Server.Services.CombatService)
local ComboService = require(script.Parent.Parent.ComboService)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StatTypes = require(ReplicatedStorage.Shared.StatTypes)

local Punch = {}
Punch.__index = Punch

setmetatable(Punch, { __index = BaseComboSkill })

local DEFAULT_STAMINA_COSTS = { 12, 16, 22 }

function Punch.new(caster: Instance, data: any)
	local self = BaseComboSkill.new(caster, data)
	setmetatable(self, Punch)
	return self
end

local function resolveCost(config, step: number): number
	local costConfig = config and config.staminaCost
	if typeof(costConfig) == "table" then
		return costConfig[step] or costConfig[#costConfig] or 0
	elseif typeof(costConfig) == "number" then
		return costConfig
	end
	return DEFAULT_STAMINA_COSTS[step] or DEFAULT_STAMINA_COSTS[#DEFAULT_STAMINA_COSTS]
end

function Punch:use(requestData: any?)
	local comboData = requestData and requestData.combo
	local step = comboData and comboData.step or 1
	local cost = resolveCost(self.config, step)
	if cost > 0 then
		local current = StatsManager.getPoolCurrentValue(self.caster, StatTypes.PoolStats.Stamina) or 0
		if current + 1e-3 < cost then
			if comboData then
				ComboService.clear(self.caster, self.name)
			end
			return
		end
		StatsManager.removeFromPool(self.caster, StatTypes.PoolStats.Stamina, cost)
	end

	BaseComboSkill.use(self, requestData)
end

local function casterOriginCFrame(skill: any): CFrame?
	local root = skill:getCasterRootPart()
	if not root then
		return nil
	end
	return root.CFrame
end

function Punch:onComboStep(step: number)
	-- Derive physical damage from server-side stats
	local baseDamage = StatsManager.getStatValue(self.caster, StatTypes.StaticStats.PhysicalDamage) or 0

	-- Simple multipliers per combo step: jab, cross, heavy
	local mult = if step == 3 then 1.25 elseif step == 2 then 0.9 else 0.8
	local coneRange = if step == 3 then 6 else 4.5
	local damage = baseDamage * mult

	local origin = casterOriginCFrame(self)
	if origin then
		local casterPlayer = self:getCasterPlayer()
		local targets = HitboxService.newQuery(origin)
			:caster(casterPlayer)
			:teamRelation("enemy")
			:playersOnly(false)
			:cone(65, coneRange)
			:collect(true)

		for _, m in ipairs(targets) do
			-- for debugging
			print("FOUND TARGET: " .. m.Name .. " for damage: " .. damage)
			CombatService.applyDamage(m, damage, self.caster)
		end
	end
end

return Punch
