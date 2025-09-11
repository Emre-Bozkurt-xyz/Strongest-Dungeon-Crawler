local BaseSkill = require(script.Parent.BaseSkill)
local StatsManager = require(script.Parent.Parent.Parent.StatsManager)
local HitboxService = require(script.Parent.Parent.Parent:WaitForChild("skills"):WaitForChild("HitboxService"))
local CombatService = require(script.Parent.Parent.Parent:WaitForChild("CombatService"))
local ComboService = require(script.Parent.Parent.ComboService)
local CooldownService = require(script.Parent.Parent.CooldownService)

local Punch = {}
Punch.__index = Punch

setmetatable(Punch, {
	__index = BaseSkill,
})

function Punch.new(player: Player, data: any)
	local self = BaseSkill.new(player, data)
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

function Punch:use(requestData: any?)
	local combo = requestData and requestData.combo
	local step = combo and combo.step or 1
	local total = combo and combo.total or 1
	local window = combo and combo.window or 0
	local token = combo and combo.token or 0

	local isFirst = (step == 1)
	local isFinal = (step == total)

	-- Close any previous idle wait if continuing
	if not isFirst then
		self:emitComboWaitEnd()
	end

	-- Only emit start once per chain
	if isFirst then
		self:emitStart({ step = step, total = total })
	end

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
		local targets =
			HitboxService.queryCone(origin, 40, 5, { caster = self.player, playersOnly = true, teamRelation = "enemy" })
		self:emitImpact(step, origin)
		for _, m in ipairs(targets) do
			CombatService.applyDamage(m, damage, self.player)
		end
	else
		self:emitImpact(step)
	end

	-- If more steps remain, open wait window & schedule expiry
	if not isFinal and window > 0 then
		local capturedStep = step
		self:emitComboWaitStart(window, step, total)
		task.delay(window, function()
			-- If chain expired without next press, close wait + send end once
			if ComboService.isExpired(self.player, self.name, token) then
				self:emitComboWaitEnd()
				self:emitEnd({ step = capturedStep, total = total, expired = true })
				-- start cooldown on early expiry
				local cfg = require(script.Parent.Parent.SkillsConfig).skills[self.name]
				local comboCfg = cfg and cfg.combo
				if comboCfg then
					local finalCd = comboCfg.comboCooldown or cfg.cooldown
					if finalCd and finalCd > 0 then
						CooldownService.start(self.player, self.name, finalCd)
					end
				end
			end
		end)
	end

	-- Emit end only on final step (or on expiry via above)
	if isFinal then
		self:emitEnd({ step = step, total = total })
	end
end

return Punch
