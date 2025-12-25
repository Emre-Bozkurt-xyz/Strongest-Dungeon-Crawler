local Server = game:GetService("ServerScriptService").Server

local BaseComboSkill = require(script.Parent.BaseComboSkill)
local HitboxService = require(script.Parent.Parent.HitboxService)
local CombatService = require(Server.Services.CombatService)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StatTypes = require(ReplicatedStorage.Shared.StatTypes)

local Punch = {}
Punch.__index = Punch

setmetatable(Punch, { __index = BaseComboSkill })

local DEBUG_HITS = false

function Punch.new(casterId: string, data: any)
	local self = BaseComboSkill.new(casterId, data)
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
	-- Derive physical damage from server-side stats via SkillMediator
	local baseDamage = self:resolveStat(StatTypes.StaticStats.PhysicalDamage, {
		step = step,
	})

	-- Simple multipliers per combo step: jab, cross, heavy
	local mult = if step == 3 then 1.25 elseif step == 2 then 0.9 else 0.8
	local coneRange = if step == 3 then 6 else 4.5
	local damage = baseDamage * mult

	local origin = casterOriginCFrame(self)
	if origin then
		local targets = HitboxService.newQuery(origin)
			:casterEntityId(self.casterId)
			:factionRelation("enemy")
			:playersOnly(false)
			:cone(65, coneRange)
			:collect({ collectIds = true, debug = true })

		-- Build attack composition (damage + potential effects via resolver later)
		local attack = self:resolveAttack({
			damage = damage,
			damageType = "Physical",
			comboStep = step,
		})

		-- Apply to all targets hit
		for _, targetEntityId in ipairs(targets.ids) do
			if DEBUG_HITS then
				print(`[Punch] Attacking entity {targetEntityId} with {damage} Physical damage (step {step})`)
			end
			CombatService.applyAttack(targetEntityId, attack, self.casterId)
		end
	end
end

return Punch
