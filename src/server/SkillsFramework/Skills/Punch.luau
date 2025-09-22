local BaseComboSkill = require(script.Parent.BaseComboSkill)
local StatsManager = require(script.Parent.Parent.Parent.StatsManager)
local HitboxService = require(script.Parent.Parent.Parent:WaitForChild("skills"):WaitForChild("HitboxService"))
local CombatService = require(script.Parent.Parent.Parent:WaitForChild("CombatService"))

local Punch = {}
Punch.__index = Punch

setmetatable(Punch, { __index = BaseComboSkill })

function Punch.new(player: Player, data: any)
	local self = BaseComboSkill.new(player, data)
	setmetatable(self, Punch)
	return self
end

local function casterOriginCFrame(player: Player): CFrame?
	local char = player.Character
	local hrp = char and (char:FindFirstChild("HumanoidRootPart") :: BasePart?)
	if not hrp then
		return nil
	end
	return (hrp :: BasePart).CFrame
end

function Punch:onComboStep(step: number)
	-- Derive physical damage from server-side stats
	local stats = StatsManager.getAllStats(self.player)
	local baseDamage = 0
	if stats and stats.PhysicalDamage then
		baseDamage = stats.PhysicalDamage:getValue(stats)
	end

	-- Simple multipliers per combo step: jab, cross, heavy
	local mult = if step == 3 then 1.25 elseif step == 2 then 0.9 else 0.8
	local damage = baseDamage * mult

	local origin = casterOriginCFrame(self.player)
	if origin then
		local targets = HitboxService.newQuery(origin)
			:caster(self.player)
			:teamRelation("enemy")
			:playersOnly(false)
			:box(Vector3.new(3, 3, 3))
			:offset(0, 0, -3)
			:collect(true)

		for _, m in ipairs(targets) do
			-- for debugging
			print("FOUND TARGET: " .. m.Name .. " for damage: " .. damage)
			CombatService.applyDamage(m, damage, self.player)
		end
	else
		self:emitFX(step, { lifetime = 1 })
	end
end

return Punch
