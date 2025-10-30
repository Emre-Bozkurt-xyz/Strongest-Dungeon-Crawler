--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Server = game:GetService("ServerScriptService").Server

local BaseSkill = require(script.Parent.BaseSkill)
local HitboxService = require(script.Parent.Parent.HitboxService)
local CombatService = require(Server.Services.CombatService)
local StatTypes = require(ReplicatedStorage.Shared.StatTypes)

local SinglePunch = {}
SinglePunch.__index = SinglePunch

setmetatable(SinglePunch, { __index = BaseSkill })

function SinglePunch.new(casterId: string, data: any)
	local self = BaseSkill.new(casterId, data)
	setmetatable(self, SinglePunch)
	return self
end

function SinglePunch:use()
	local timing = self:resolveTiming()

	if not self:applyResourceCost({ timing = timing }) then
		return
	end

	local baseDuration = self.config.baseDuration or 1.0
	local durationScale = timing.durationScale

	local executionDuration = baseDuration * durationScale

	self:beginExecution(executionDuration, {
		lockJump = true,
		allowChain = false,
		autoComplete = false,
		timing = timing,
	})

	local baseDamage = self:queryStatValue(StatTypes.StaticStats.PhysicalDamage) or 0

	local origin = self:getCasterOriginCFrame(self)

	local range = self.config.hit.coneRange
	local angle = self.config.hit.coneAngle

	local targets =
		HitboxService.newQuery(origin):caster(self:getCasterPlayer()):teamRelation("enemy"):cone(angle, range):collect()

	for _, target in ipairs(targets) do
		CombatService.applyDamage(target, baseDamage, self.caster)
	end

	if executionDuration and executionDuration > 0 then
		task.delay(executionDuration, function()
			self:completeExecution()
		end)
	else
		task.defer(function()
			self:completeExecution()
		end)
	end
end

return SinglePunch
