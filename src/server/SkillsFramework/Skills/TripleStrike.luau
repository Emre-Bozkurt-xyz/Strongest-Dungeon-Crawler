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

local function getPhysicalDamage(player: Player): number
	local stats = StatsManager.getAllStats(player)
	if not stats then
		return 0
	end
	local s = stats.PhysicalDamage
	if s then
		return s:getValue(stats)
	end
	return 0
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
	local player = self.player
	local base = getPhysicalDamage(player)

	self:emitStart()

	-- Schedule three directional cones: center, left, right
	self:schedule({
		{
			t = 0.10,
			fn = function()
				local originCf = casterOriginCFrame(player, 0)
				local targets = {}
				if originCf then
					if DEBUG_VIS then
						HitboxService.debugDrawRay(originCf, 8, 0.25)
					end
					targets = HitboxService.newQuery(originCf)
						:caster(player)
						:teamRelation("enemy")
						:playersOnly(true)
						:cone(50, 8)
						:collect()
				end
				self:emitImpact(1, originCf)
				for _, model in ipairs(targets) do
					CombatService.applyDamage(model, base * 0.8, player)
				end
			end,
		},
		{
			t = 0.25,
			fn = function()
				local originCf = casterOriginCFrame(player, -25)
				local targets = {}
				if originCf then
					if DEBUG_VIS then
						HitboxService.debugDrawRay(originCf, 8, 0.25)
					end
					targets = HitboxService.newQuery(originCf)
						:caster(player)
						:teamRelation("enemy")
						:playersOnly(true)
						:cone(50, 8)
						:collect()
				end
				self:emitImpact(2, originCf)
				for _, model in ipairs(targets) do
					CombatService.applyDamage(model, base * 1.0, player)
				end
			end,
		},
		{
			t = 0.40,
			fn = function()
				local originCf = casterOriginCFrame(player, 25)
				local targets = {}
				if originCf then
					if DEBUG_VIS then
						HitboxService.debugDrawRay(originCf, 8, 0.25)
					end
					targets = HitboxService.newQuery(originCf)
						:caster(player)
						:teamRelation("enemy")
						:playersOnly(true)
						:cone(50, 8)
						:collect()
				end
				self:emitImpact(3, originCf)
				for _, model in ipairs(targets) do
					CombatService.applyDamage(model, base * 1.2, player)
				end
			end,
		},
	})

	-- Optionally, emit end slightly after last impact
	task.delay(0.45, function()
		self:emitEnd()
	end)
end

return TripleStrike
