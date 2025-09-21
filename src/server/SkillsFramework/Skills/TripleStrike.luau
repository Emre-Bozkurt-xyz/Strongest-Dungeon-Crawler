--!strict
local BaseSkill = require(script.Parent:WaitForChild("BaseSkill"))
local StatsManager = require(script.Parent.Parent.Parent:WaitForChild("StatsManager"))
local HitboxService = require(script.Parent.Parent.Parent:WaitForChild("skills"):WaitForChild("HitboxService"))
local CombatService = require(script.Parent.Parent.Parent:WaitForChild("CombatService"))

local DEBUG_VIS = false

local TripleStrike = {}
TripleStrike.__index = TripleStrike

setmetatable(TripleStrike, { __index = BaseSkill })

function TripleStrike.new(player: Player, data: any)
	local self = BaseSkill.new(player, data)
	setmetatable(self, TripleStrike)
	self.cooldown = data.cooldown or 5
	self.gcd = data.gcd or 1.0
	return self
end

local function casterOriginCFrame(player: Player, yawOffsetDeg: number?): CFrame?
	local character = player.Character
	local hrp = character and (character:FindFirstChild("HumanoidRootPart") :: BasePart?)
	if not hrp then
		return nil
	end
	local yaw = math.rad(yawOffsetDeg or 0)
	local baseCf = (hrp :: BasePart).CFrame
	return baseCf * CFrame.Angles(0, yaw, 0)
end

function TripleStrike:use()
	local stats = StatsManager.getAllStats(self.player)
	local base = 0
	if stats and stats.PhysicalDamage then
		base = stats.PhysicalDamage:getValue(stats)
	end

	self:emitStart()

	local hits = (self.config and self.config.hits) :: { any }?
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
					local playersOnly = if h.playersOnly == nil then true else h.playersOnly
					local mult = (h.damageMult or 1.0) :: number

					local originCf = casterOriginCFrame(self.player, yaw)
					local targets = {}
					if originCf then
						if DEBUG_VIS then
							HitboxService.debugDrawRay(originCf, range, 0.25)
						end
						local q = HitboxService.newQuery(originCf)
							:caster(self.player)
							:teamRelation("enemy")
							:playersOnly(playersOnly)
							:cone(angle, range)
						targets = q:collect()
					end
					self:emitFX(i, { cframe = originCf, lifetime = 1 })
					for _, model in ipairs(targets) do
						CombatService.applyDamage(model, base * mult, self.player)
					end
				end,
			}
		end
		self:schedule(steps)
		local lastT = hits[#hits].t or 0
		task.delay(lastT + 0.05, function()
			self:emitEnd()
		end)
		return
	end
end

return TripleStrike
