local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Server = game:GetService("ServerScriptService").Server

local Timeline = require(script.Parent.Parent.Timeline)
local ExecutionService = require(script.Parent.Parent.ExecutionService)
local Registrar = require(Server.Services.Registrar)
local event = require(script.Parent.Parent.SkillsEvent)
local StatsManager = require(Server.Stats.StatsManager)
local ComboService = require(Server.SkillsFramework.ComboService)
local StatTypes = require(ReplicatedStorage.Shared.StatTypes)
local SkillTimingService = require(script.Parent.Parent.SkillTimingService)

local BaseSkill = {}
BaseSkill.__index = BaseSkill

function BaseSkill.new(entityId: string, data: any)
	local self = setmetatable({}, BaseSkill)
	self.casterId = entityId
	self.caster = Registrar.getEntityById(entityId)
	self.id = data.id or data.name
	self.name = data.name
	self.description = data.description
	self.level = data.level or 1
	self.cooldown = data.cooldown or 0
	self.gcd = data.gcd or 1.0
	-- Keep full server-side config for timing and other logic
	self.config = data
	self._execToken = nil
	self._execState = nil
	self._lastTiming = nil
	return self
end

local function cloneTable(source: { [any]: any }?): { [any]: any }
	local target: { [any]: any } = {}
	if not source then
		return target
	end
	for key, value in pairs(source) do
		target[key] = value
	end
	return target
end

function BaseSkill:_buildSkillMetadata(extra: { [any]: any }?, overrides: { [any]: any }?): { [any]: any }
	local metadata = {}
	metadata.skill = self.name
	metadata.skillId = self.id
	metadata.skillCategory = self.config and self.config.category or nil
	metadata.skillTags = self.config and (self.config.tags or self.config.categories) or nil
	metadata.casterId = self.casterId

	local overrideMeta = overrides and overrides.metadata or nil
	if overrideMeta then
		for key, value in pairs(overrideMeta) do
			metadata[key] = value
		end
	end

	if extra then
		for key, value in pairs(extra) do
			metadata[key] = value
		end
	end

	return metadata
end

function BaseSkill:_buildSkillQueryOptions(defaultEvent: string, extraMetadata: { [any]: any }?, overrides)
	local options = if overrides then cloneTable(overrides) else {}
	if overrides and overrides.metadata then
		options.metadata = cloneTable(overrides.metadata)
	end
	options.metadata = self:_buildSkillMetadata(extraMetadata, options)
	if defaultEvent and options.event == nil then
		options.event = defaultEvent
	end
	return options
end

function BaseSkill:queryStatValue(statType: any, metadata: { [any]: any }?, overrides)
	local options = self:_buildSkillQueryOptions("skillStatQuery", metadata, overrides)
	return StatsManager.getStatValue(self.casterId, statType, options)
end

function BaseSkill:queryPoolCurrent(poolType: any, metadata: { [any]: any }?, overrides)
	local options = self:_buildSkillQueryOptions("resolveSkillResource", metadata, overrides)
	return StatsManager.getPoolCurrentValue(self.casterId, poolType, options)
end

function BaseSkill:queryPoolMax(poolType: any, metadata: { [any]: any }?, overrides)
	local options = self:_buildSkillQueryOptions("resolveSkillResourceMax", metadata, overrides)
	return StatsManager.getPoolMaxValue(self.casterId, poolType, options)
end

function BaseSkill:resolveTiming()
	-- Simplified: timing service now infers tempo and durationScale from skill tags and entity stats.
	return SkillTimingService.resolve(self.casterId, self.name)
end

function BaseSkill:_captureTiming(timing: { [string]: any }?)
	if timing == nil then
		self._lastTiming = nil
		return
	end
	self._lastTiming = timing
end

function BaseSkill:_updateExecutionState(update: { [string]: any }?)
	if update == nil or type(update) ~= "table" then
		return
	end
	if update.timing then
		self:_captureTiming(update.timing)
	end
	if not self._execToken then
		return
	end
	local payload = table.clone(update)
	if payload.timing and type(payload.timing) == "table" then
		-- only propagate essential timing fields (durationScale). For backwards compatibility
		-- we also compute a tempo value as 1/durationScale when needed.
		payload.timing = { durationScale = payload.timing.durationScale }
		if payload.durationScale == nil and payload.timing.durationScale then
			payload.durationScale = payload.timing.durationScale
		end
		if payload.tempo == nil and payload.timing.durationScale then
			local ds = payload.timing.durationScale
			if type(ds) == "number" and ds ~= 0 then
				payload.tempo = 1 / ds
			end
		end
	end
	if payload.metadata and type(payload.metadata) == "table" then
		payload.metadata = cloneTable(payload.metadata)
	end
	if payload.targetDuration == nil and type(payload.stepDuration) == "number" then
		payload.targetDuration = payload.stepDuration
	end
	ExecutionService.annotate(self.caster, self._execToken, payload)
	local state = self._execState
	if state then
		for key, value in pairs(payload) do
			state[key] = value
		end
	end
end

-- function BaseSkill:applyResourceCost(poolType: any, amount: number, metadata: { [any]: any }?, overrides)
-- 	local meta = metadata or {}
-- 	meta.baseCost = amount

-- 	local options = self:_buildSkillQueryOptions("resolveSkillCost", meta, overrides)
-- 	return StatsManager.removeFromPool(self.caster, poolType, amount, options)
-- end

function BaseSkill:getBaseCost(data: any?): number
	local comboConfig = data and data.combo or nil

	local cost = self.config.cost or 0

	-- Determine cost based on combo step if applicable
	if comboConfig then
		local step = comboConfig.step
		local costConfig = self.config and self.config.costs
		if typeof(costConfig) == "table" then
			cost = costConfig[step] or costConfig[#costConfig] or 0
		elseif typeof(costConfig) == "number" then
			cost = costConfig
		end
	end

	return cost
end

function BaseSkill:applyResourceCost(data: any?): boolean
	local comboConfig = data and data.combo or nil

	local cost = self:getBaseCost(data)

	-- Determine base resource to be consumed
	local baseResource = self.config and self.config.baseResource or StatTypes.PoolStats.Stamina

	-- No cost to apply
	if cost <= 0 then
		return true
	end

	-- Preview cost to determine actual pool and final cost after observers' modification
	local timingInfo = data and data.timing
	local costMetadata = {
		resource = baseResource,
		step = comboConfig and comboConfig.step or nil,
	}
	if timingInfo then
		-- Provide durationScale to cost observers explicitly (tempo is derivable as 1/durationScale)
		costMetadata.durationScale = timingInfo.durationScale
		if timingInfo.metadata then
			costMetadata.timingMetadata = timingInfo.metadata
		end
	end

	local preview = self:previewResourceCost(baseResource, cost, costMetadata)
	local targetPool = baseResource
	local finalCost = cost
	local currentValue = 0
	local removalOverrides = nil

	if preview then
		targetPool = preview.poolName
		finalCost = preview.finalCost
		currentValue = preview.currentValue
		local overrideMeta = table.clone(preview.metadata or {})
		overrideMeta.resource = targetPool
		removalOverrides = {
			metadata = overrideMeta,
			overrideStat = if targetPool ~= baseResource then targetPool else nil,
		}
	else
		currentValue = self:queryPoolCurrent(baseResource, {
			resource = baseResource,
			step = comboConfig and comboConfig.step or nil,
		}) or 0
	end

	if currentValue + 1e-3 < finalCost then
		if comboConfig then
			ComboService.clear(self.caster, self.name)
		end
		return false
	end

	local removalMetadata = {
		resource = targetPool,
		step = comboConfig and comboConfig.step or nil,
		baseCost = finalCost,
	}

	local options = self:_buildSkillQueryOptions("applySkillCost", removalMetadata, removalOverrides)
	StatsManager.removeFromPool(self.caster, targetPool, finalCost, options)

	return true
end

function BaseSkill:previewResourceCost(poolType: any, amount: number, metadata: { [any]: any }?, overrides)
	local options = self:_buildSkillQueryOptions("resolveSkillCost", metadata, overrides)
	return StatsManager.resolvePoolCost(self.caster, poolType, amount, options)
end

function BaseSkill:use()
	-- child should override
	error("BaseSkill:use() must be implemented by child: " .. tostring(self.name))
end

-- Emit a start phase; children can override before/after
function BaseSkill:emitStart(extra: any?)
	event:FireAllClients({ phase = "start", id = self.name, casterId = self._casterUserId, data = extra })
end

-- Emit an impact with optional cframe/targets and step index
-- Emit a generic FX signal (replaces old 'impact')
-- params:
--   step: number (combo step or sequence index)
--   opts: { cframe: CFrame?, anchor: { mode: string, name: string, offset: CFrame?, fallback: string? }?, fxKey: string?, lifetime: number?, meta: any? }
function BaseSkill:emitFX(step: number, opts: any?)
	local o = opts or {}
	event:FireAllClients({
		phase = "fx",
		id = self.name,
		casterId = self._casterUserId,
		step = step,
		cframe = o.cframe,
		anchor = o.anchor,
		fxKey = o.fxKey,
		lifetime = o.lifetime,
		data = o.meta,
	})
end

-- Emit a step begin (for playing combo step animations client-side)
function BaseSkill:emitStep(step: number, extra: any?)
	event:FireAllClients({
		phase = "step",
		id = self.name,
		casterId = self._casterUserId,
		step = step,
		data = extra,
	})
end

-- Emit an end/cleanup
function BaseSkill:emitEnd(extra: any?)
	event:FireAllClients({ phase = "end", id = self.name, casterId = self._casterUserId, data = extra })
end

-- Combo helpers: open/close combo wait window for client idle anims
function BaseSkill:emitComboWaitStart(durationSec: number, step: number, totalSteps: number)
	event:FireAllClients({
		phase = "combo_wait",
		open = true,
		id = self.name,
		casterId = self._casterUserId,
		step = step,
		total = totalSteps,
		duration = durationSec,
	})
end

function BaseSkill:emitComboWaitEnd()
	event:FireAllClients({ phase = "combo_wait", open = false, id = self.name, casterId = self._casterUserId })
end

function BaseSkill:schedule(steps: { { t: number, fn: () -> () } })
	local tl = Timeline.new()
	tl:sequence(steps)
	return tl
end

export type ExecutionOptions = {
	autoComplete: boolean?,
	allowChain: boolean?,
	speedMult: number?,
	timing: { [string]: any }?,
	lockJump: boolean?,
}

-- Execution helpers: wrap emitStart/emitEnd with execution lock semantics.
-- duration: optional planned execution length (auto-completes). If nil, skill must call completeExecution manually.
function BaseSkill:beginExecution(duration: number?, opts: ExecutionOptions)
	if self._execToken then
		return
	end -- already executing
	-- Compute tempo for ExecutionService from timing.durationScale (tempo == 1/durationScale)
	local tempo = opts.speedMult or nil
	if
		tempo == nil
		and opts.timing
		and type(opts.timing.durationScale) == "number"
		and opts.timing.durationScale ~= 0
	then
		tempo = 1 / opts.timing.durationScale
	end
	local token, state = ExecutionService.begin(self.caster, self.name, {
		duration = duration,
		allowChainSkill = opts.allowChain and self.name or nil,
		tempo = tempo,
		durationScale = opts.timing and opts.timing.durationScale or nil,
		timing = opts.timing,
		targetDuration = duration,
		lockJump = opts.lockJump,
	})
	if not token then
		return false
	end
	self._execToken = token
	self._execState = state
	if opts.timing then
		self:_captureTiming(opts.timing)
	end
	local startTempo = tempo or 1
	local startDuration = if state and state.targetDuration
		then state.targetDuration
		elseif duration and duration > 0 then duration
		else state and state.plannedDuration or nil
	local startData = {
		tempo = startTempo,
		speed = startTempo,
		duration = duration,
		plannedDuration = duration,
		durationScale = opts.timing and opts.timing.durationScale or (state and state.durationScale),
		-- Removed baseDuration
		startedAt = state and state.startedAt or nil,
		finishAt = state and state.finishAt or nil,
		targetDuration = startDuration,
	}
	self:emitStart(startData)
	return true
end

function BaseSkill:completeExecution(reason: string?)
	if not self._execToken then
		return
	end
	local tok = self._execToken
	local state = self._execState
	self._execToken = nil
	self._execState = nil
	ExecutionService.complete(self.caster, tok, reason)
	local finishedAt = state and state.completedAt or os.clock()
	local startedAt = state and state.startedAt or nil
	local elapsed = nil
	if startedAt then
		elapsed = math.max(0, finishedAt - startedAt)
	end
	local timing = self._lastTiming
	local durationScale = state and state.durationScale or (timing and timing.durationScale)
	local tempo = state and state.tempo or (durationScale and durationScale ~= 0 and 1 / durationScale) or nil
	local endData = {
		reason = reason,
		tempo = tempo,
		durationScale = durationScale,
		timingMetadata = nil,
		startedAt = startedAt,
		finishedAt = finishedAt,
		elapsed = elapsed,
		targetDuration = state and state.targetDuration or (state and state.plannedDuration) or nil,
	}
	if state and state.plannedDuration then
		endData.duration = state.plannedDuration
	end
	self:emitEnd(endData)
	self._lastTiming = nil
end

function BaseSkill:getCasterPlayer(): Player?
	return self.player
end

function BaseSkill:getCasterModel(): Model?
	if self.player then
		return self.player.Character
	end
	if self.caster:IsA("Model") then
		return self.caster
	end
	return self.caster:FindFirstAncestorOfClass("Model")
end

function BaseSkill:getCasterRootPart(): BasePart?
	local model = self:getCasterModel()
	if model then
		return model:FindFirstChild("HumanoidRootPart") :: BasePart?
	end
	return nil
end

function BaseSkill:getCasterOriginCFrame(yaw: number?): CFrame?
	local root = self:getCasterRootPart()
	if not root then
		return nil
	end
	return root.CFrame * CFrame.Angles(0, math.rad(yaw or 0), 0)
end

return BaseSkill
