--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Server = game:GetService("ServerScriptService").Server

local BaseSkill = require(script.Parent:WaitForChild("BaseSkill"))
local HitboxService = require(Server.SkillsFramework.HitboxService)
local CombatService = require(Server.Services.CombatService)
local StatTypes = require(ReplicatedStorage.Shared.StatTypes)

local DEBUG_VIS = true

local TripleStrike = {}
TripleStrike.__index = TripleStrike

setmetatable(TripleStrike, { __index = BaseSkill })

function TripleStrike.new(caster: Instance, data: any)
	local self = BaseSkill.new(caster, data)
	setmetatable(self, TripleStrike)
	self.cooldown = data.cooldown or 5
	self.gcd = data.gcd or 1.0
	return self
end

function TripleStrike:use()
	local hits = (self.config and self.config.hits) :: { any }?
	local tail = 0.05
	local baseTimelineDuration = 0
	local baseOverride = if self.config and typeof((self.config :: any).baseDuration) == "number" then (self.config :: any).baseDuration else nil
	if type(hits) == "table" and #hits > 0 then
		local lastT = hits[#hits].t or 0
		baseTimelineDuration = lastT + tail
	end
	if baseOverride and baseOverride > 0 then
		baseTimelineDuration = baseOverride
	end

	local timing = self:resolveTiming({
		metadata = {
			baseDuration = baseTimelineDuration,
			tail = tail,
			hitCount = type(hits) == "table" and #hits or 0,
		},
	})

	if not self:applyResourceCost({ timing = timing }) then
		return
	end

	local tempo = timing.tempo
	local durationScale = timing.durationScale

	local executionDuration = baseTimelineDuration * durationScale
	local planned = executionDuration > 0 and executionDuration or nil
	local stepTarget = planned or executionDuration
	self:beginExecution(planned, false, tempo, timing)
	self:_updateExecutionState({
		timing = timing,
		tempo = tempo,
		durationScale = durationScale,
		plannedDuration = planned,
		targetDuration = planned,
	})

	local baseDamage = self:queryStatValue(StatTypes.StaticStats.PhysicalDamage, {
		event = "skillDamageQuery",
		metadata = {
			stepCount = type(hits) == "table" and #hits or 0,
		},
	}) or 0

	if type(hits) == "table" and #hits > 0 then
		local steps = {}
		for i, h in ipairs(hits) do
			local baseTime = (h.t or 0) :: number
			local scheduledTime = baseTime * durationScale
			steps[#steps + 1] = {
				t = scheduledTime,
				fn = function()
					self:emitStep(i, {
						tempo = tempo,
						speed = tempo,
						durationScale = durationScale,
						baseTime = baseTime,
						scheduledTime = scheduledTime,
						targetDuration = stepTarget,
					})
					local yaw = (h.yaw or 0) :: number
					local angle = (h.coneAngle or 50) :: number
					local range = (h.coneRange or 8) :: number
					local mult = (h.damageMult or 1.0) :: number

					local originCf = self:getCasterOriginCFrame(yaw)
					local targets = {}
					if originCf then
						local casterPlayer = self:getCasterPlayer()
						local q = HitboxService.newQuery(originCf)
							:caster(casterPlayer)
							:teamRelation("enemy")
							:playersOnly(false)
							:cone(angle, range)
						targets = q:collect(DEBUG_VIS)
					end
					self:emitFX(i, { cframe = originCf, lifetime = 1 })
					for _, model in ipairs(targets) do
						local damage = baseDamage * mult
						CombatService.applyDamage(model, damage, self.caster)
						print(
							`TripleStrike hit {model.Name} for {baseDamage} * {mult} = {damage} damage (base {baseDamage}, mult {mult})`
						)
					end
				end,
			}
		end
		self:schedule(steps)
		if planned and planned > 0 then
			task.delay(planned, function()
				self:completeExecution()
			end)
		else
			task.defer(function()
				self:completeExecution()
			end)
		end
		return
	end
end

return TripleStrike
