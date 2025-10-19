--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BaseSkill = require(script.Parent:WaitForChild("BaseSkill"))
local StatsManager = require(script.Parent.Parent.Parent:WaitForChild("StatsManager"))
local HitboxService = require(script.Parent.Parent.HitboxService)
local CombatService = require(script.Parent.Parent.Parent:WaitForChild("CombatService"))
local StatTypes = require(ReplicatedStorage.Shared.StatTypes)

local DEBUG_VIS = false

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
	local stats = StatsManager.getAllStats(self.caster)
	local base = 0
	local physKey = StatTypes.StaticStats.PhysicalDamage
	if stats then
		local physicalDamage = stats[physKey]
		if physicalDamage and physicalDamage.getValue then
			base = physicalDamage:getValue(stats)
		end
	end

	-- Determine total planned execution duration (last hit time + small tail)
	local hits = (self.config and self.config.hits) :: { any }?
	local tail = 0.05
	local totalDuration = 0
	if type(hits) == "table" and #hits > 0 then
		local lastT = hits[#hits].t or 0
		totalDuration = lastT + tail
	end
	self:beginExecution(totalDuration > 0 and totalDuration or nil, false)

	if type(hits) == "table" and #hits > 0 then
		local steps = {}
		for i, h in ipairs(hits) do
			local t = (h.t or 0) :: number
			steps[#steps + 1] = {
				t = t,
				fn = function()
					-- announce step for client animations
					self:emitStep(i)
					local yaw = (h.yaw or 0) :: number
					local angle = (h.coneAngle or 50) :: number
					local range = (h.coneRange or 8) :: number
					local mult = (h.damageMult or 1.0) :: number

					local originCf = self:getCasterOriginCFrame(yaw)
					local targets = {}
					if originCf then
						if DEBUG_VIS then
							HitboxService.debugDrawRay(originCf, range, 0.25)
						end
						local casterPlayer = self:getCasterPlayer()
						local q = HitboxService.newQuery(originCf)
							:caster(casterPlayer)
							:teamRelation("enemy")
							:playersOnly(false)
							:cone(angle, range)
						targets = q:collect(true)
					end
					self:emitFX(i, { cframe = originCf, lifetime = 1 })
					for _, model in ipairs(targets) do
						CombatService.applyDamage(model, base * mult, self.caster)
						print(
							`TripleStrike hit {model.Name} for {base} * {mult} = {base * mult} damage (base {base}, mult {mult})`
						)
					end
				end,
			}
		end
		self:schedule(steps)
		task.delay(totalDuration, function()
			self:completeExecution()
		end)
		return
	end
end

return TripleStrike
