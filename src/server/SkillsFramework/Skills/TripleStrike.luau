local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Server = game:GetService("ServerScriptService").Server

local BaseSkill = require(script.Parent:WaitForChild("BaseSkill"))
local HitboxService = require(Server.SkillsFramework.HitboxService)
local CombatService = require(Server.Services.CombatService)
local StatTypes = require(ReplicatedStorage.Shared.StatTypes)

local DEBUG_VIS = false

local TripleStrike = {}
TripleStrike.__index = TripleStrike

setmetatable(TripleStrike, { __index = BaseSkill })

function TripleStrike.new(casterId: string, data: any)
	local self = BaseSkill.new(casterId, data)
	setmetatable(self, TripleStrike)
	self.cooldown = data.cooldown or 5
	self.gcd = data.gcd or 1.0
	return self
end

function TripleStrike:use(requestData: any?)
	local hits = (self.config and self.config.hits) :: { any }?
	local tail = 0.05
	local baseTimelineDuration = 0
	local baseOverride = if self.config and typeof((self.config :: any).baseDuration) == "number"
		then (self.config :: any).baseDuration
		else nil
	if type(hits) == "table" and #hits > 0 then
		local lastT = hits[#hits].t or 0
		baseTimelineDuration = lastT + tail
	end
	if baseOverride and baseOverride > 0 then
		baseTimelineDuration = baseOverride
	end

	local timing = self:resolveTiming()

	if not self:applyResourceCost({ timing = timing }) then
		return
	end

	local durationScale = timing.durationScale
	local tempo = durationScale and durationScale ~= 0 and (1 / durationScale) or 1

	local executionDuration = baseTimelineDuration * durationScale
	local planned = executionDuration > 0 and executionDuration or nil
	local _stepTarget = planned or executionDuration
	self:beginExecution(planned, { timing = timing, sessionId = requestData and requestData.sessionId or nil })
	self:_updateExecutionState({
		timing = timing,
		tempo = tempo,
		durationScale = durationScale,
		plannedDuration = planned,
		targetDuration = planned,
	})

	local baseDamage = self:resolveStat(StatTypes.StaticStats.PhysicalDamage, {
		stepCount = type(hits) == "table" and #hits or 0,
	})

	if type(hits) == "table" and #hits > 0 then
		local steps = {}
		for hitIndex, h in ipairs(hits) do
			local baseTime = (h.t or 0) :: number
			local scheduledTime = baseTime * durationScale
			steps[#steps + 1] = {
				t = scheduledTime,
				fn = function()
					local yaw = (h.yaw or 0) :: number
					local angle = (h.coneAngle or 50) :: number
					local range = (h.coneRange or 8) :: number
					local mult = (h.damageMult or 1.0) :: number

					local originCf = self:getCasterOriginCFrame(yaw)
					if originCf then
						local targets = HitboxService.newQuery(originCf)
							:casterEntityId(self.casterId)
							:factionRelation("enemy")
							:playersOnly(false)
							:cone(angle, range)
							:collect({ debug = DEBUG_VIS, collectIds = true })

						-- Build attack composition using resolver
						local damage = baseDamage * mult
						local attack = self:resolveAttack({
							damage = damage,
							damageType = "Physical",
							comboStep = hitIndex,
						})

						-- Apply to all targets
						for _, targetEntityId in ipairs(targets.ids) do
							CombatService.applyAttack(targetEntityId, attack, self.casterId)
						end
					end
				end,
			}
		end
		self:schedule(steps)
		if planned and planned > 0 then
			task.delay(planned, function()
				self:completeExecution()
			end)
		end
	end

	-- Explicit nil return to satisfy strict mode when no success payload is returned
	return nil
end

return TripleStrike
