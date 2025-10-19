local BaseComboSkill = require(script.Parent.BaseComboSkill)
local StatsManager = require(script.Parent.Parent.Parent.StatsManager)
local HitboxService = require(script.Parent.Parent.HitboxService)
local CombatService = require(script.Parent.Parent.Parent.CombatService)

local Punch = {}
Punch.__index = Punch

setmetatable(Punch, { __index = BaseComboSkill })

function Punch.new(caster: Instance, data: any)
	local self = BaseComboSkill.new(caster, data)
	setmetatable(self, Punch)
	return self
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
	local stats = StatsManager.getAllStats(self.caster)
	local baseDamage = 0
	if stats and stats.PhysicalDamage and stats.PhysicalDamage.getValue then
		baseDamage = stats.PhysicalDamage:getValue(stats)
	end

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
