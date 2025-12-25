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

function SinglePunch:use(requestData: any?)
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
		sessionId = requestData and requestData.sessionId or nil, -- Phase 3
	})

	local baseDamage = self:resolveStat(StatTypes.StaticStats.PhysicalDamage)
	-- Build attack composition using resolver
	local attack = self:resolveAttack({
		damage = baseDamage,
		damageType = "Physical",
	})

	local origin = self:getCasterOriginCFrame()

	for _, hit in ipairs(self.config.hits) do
		local range = hit.coneRange
		local angle = hit.coneAngle
		task.delay(hit.t, function()
			local targets = HitboxService.newQuery(origin)
				:casterEntityId(self.casterId)
				:factionRelation("enemy")
				:cone(angle, range)
				:collect({ collectIds = true, debug = true })
			-- Apply to all targets
			for _, targetEntityId in ipairs(targets.ids) do
				CombatService.applyAttack(targetEntityId, attack, self.casterId)
			end
		end)
	end

	-- ExecutionService auto-completes based on duration passed to beginExecution
	-- No manual completion needed

	-- Return success response for client
	return {
		success = true,
		data = {
			duration = executionDuration,
		},
	}
end

return SinglePunch
