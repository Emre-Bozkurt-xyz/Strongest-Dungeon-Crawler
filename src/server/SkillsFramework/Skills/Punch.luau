local Server = game:GetService("ServerScriptService").Server

local BaseComboSkill = require(script.Parent.BaseComboSkill)
local HitboxService = require(script.Parent.Parent.HitboxService)
local CombatService = require(Server.Services.CombatService)
local AttackResolver = require(script.Parent.Parent.AttackResolver)

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
	-- Derive damage from the currently equipped main-hand weapon (falls back to the unarmed
	-- profile when empty-handed). Weapon-scoped affix bonuses are already folded in by
	-- CombatLoadoutResolver; the global PhysicalDamage stat is added as flat damage on top.
	local damages = self:resolveWeaponDamage("main")

	-- Simple multipliers per combo step: jab, cross, heavy
	local mult = if step == 3 then 1.25 elseif step == 2 then 0.9 else 0.8
	local coneRange = if step == 3 then 6 else 4.5

	local scaled: { AttackResolver.TypedDamage } = {}
	local totalDamage = 0
	for _, entry in ipairs(damages) do
		local amount = entry.amount * mult
		table.insert(scaled, { type = entry.type, amount = amount })
		totalDamage += amount
	end

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
			damages = scaled,
			comboStep = step,
		})

		-- Apply to all targets hit
		for _, targetEntityId in ipairs(targets.ids) do
			if DEBUG_HITS then
				print(`[Punch] Attacking entity {targetEntityId} with {totalDamage} damage (step {step})`)
			end
			CombatService.applyAttack(targetEntityId, attack, self.casterId)
		end
	end
end

return Punch
