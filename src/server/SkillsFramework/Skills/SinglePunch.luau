--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Server = game:GetService("ServerScriptService").Server

local BaseSkill = require(script.Parent.BaseSkill)
local StatsManager = require(Server.Stats.StatsManager)
local HitboxService = require(script.Parent.Parent.HitboxService)
local CombatService = require(Server.Services.CombatService)
local StatTypes = require(ReplicatedStorage.Shared.StatTypes)

local SinglePunch = {}
SinglePunch.__index = SinglePunch

setmetatable(SinglePunch, { __index = BaseSkill })

local function casterOriginCFrame(skill): CFrame?
	local root = skill:getCasterRootPart()
	if not root then
		return nil
	end
	return root.CFrame
end

local function resolveHits(config: any?): { [number]: any }
	if type(config) == "table" and type(config.hits) == "table" then
		return config.hits
	end
	return {}
end

local function computeBaseDamage(caster: Instance): number
	local value = StatsManager.getStatValue(caster, StatTypes.StaticStats.PhysicalDamage)
	return value or 0
end

function SinglePunch.new(caster: Instance, data: any)
	local self = BaseSkill.new(caster, data)
	setmetatable(self, SinglePunch)
	return self
end

function SinglePunch:use()
	local hits = resolveHits(self.config)
	local tail = 0.05
	local totalDuration = 0.25
	if #hits > 0 then
		local last = hits[#hits]
		totalDuration = math.max((last.t or 0) + tail, totalDuration)
	end

	self:beginExecution(totalDuration, false)

	local baseDamage = computeBaseDamage(self.caster)
	if #hits == 0 then
		self:emitStep(1)
		self:_applyHit(baseDamage, 1, nil)
	else
		local steps = {}
		for index, hitSpec in ipairs(hits) do
			local delay = hitSpec.t or 0
			steps[#steps + 1] = {
				t = delay,
				fn = function()
					self:emitStep(index)
					self:_applyHit(baseDamage, index, hitSpec)
				end,
			}
		end
		self:schedule(steps)
	end

	task.delay(totalDuration, function()
		self:completeExecution()
	end)
end

function SinglePunch:_applyHit(baseDamage: number, step: number, hitSpec: any?)
	local origin = casterOriginCFrame(self)
	if not origin then
		return
	end

	local range = if hitSpec and hitSpec.coneRange then hitSpec.coneRange else 7
	local angle = if hitSpec and hitSpec.coneAngle then hitSpec.coneAngle else 55
	local mult = if hitSpec and hitSpec.damageMult then hitSpec.damageMult else 1
	local yaw = if hitSpec and hitSpec.yaw then math.rad(hitSpec.yaw) else 0
	local playersOnly = if hitSpec and hitSpec.playersOnly ~= nil then hitSpec.playersOnly else false

	if yaw ~= 0 then
		origin = origin * CFrame.Angles(0, yaw, 0)
	end

	local casterPlayer = self:getCasterPlayer()
	local query = HitboxService.newQuery(origin)
		:caster(casterPlayer)
		:teamRelation("enemy")
		:playersOnly(playersOnly)
		:cone(angle, range)

	local targets = query:collect(true)
	self:emitFX(step, { cframe = origin, lifetime = 0.75 })

	for _, target in ipairs(targets) do
		CombatService.applyDamage(target, baseDamage * mult, self.caster)
	end
end

return SinglePunch
