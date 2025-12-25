local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Server = game:GetService("ServerScriptService").Server
local HttpService = game:GetService("HttpService")

local Timeline = require(script.Parent.Parent.Timeline)
local SessionManager = require(script.Parent.Parent.SessionManager) -- Phase 3: Unified system
local Registrar = require(Server.Services.Registrar)
local StatsManager = require(Server.Stats.StatsManager)
local SkillMediator = require(Server.Stats.SkillMediator)
local AttackResolver = require(script.Parent.Parent.AttackResolver)
local SkillQueryTypes = require(ReplicatedStorage.Shared.skills.SkillQueryTypes)
local StatTypes = require(ReplicatedStorage.Shared.StatTypes)
local SkillTimingService = require(script.Parent.Parent.SkillTimingService)
local AttackTypes = require(ReplicatedStorage.Shared.skills.AttackTypes)

local BaseSkill = {}
BaseSkill.__index = BaseSkill

local DEBUG_PHASE3 = false -- Phase 3: Track dual-system operation

local function debugPhase3(...: any)
	if DEBUG_PHASE3 then
		print("[PHASE3-SKILL]", ...)
	end
end

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
	self._sessionId = nil -- Phase 3: Track session ID
	self._autoCompleteToken = nil
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

-- Build a standard SkillQueryContext for resolving a stat value in the context of this skill.
function BaseSkill:resolveStat(statType: any, extraMeta: { [string]: any }?): number
	local baseValue = StatsManager.getStatValue(self.casterId, statType) or 0
	local meta = cloneTable(extraMeta)
	meta.source = meta.source or "skill"
	meta.skill = self.name
	meta.skillId = self.id
	meta.skillCategory = self.config and self.config.category or nil
	meta.skillTags = self.config and (self.config.tags or self.config.categories) or nil
	meta.casterId = self.casterId

	local ctx: SkillQueryTypes.SkillQueryContext = {
		entityId = self.casterId,
		skillId = self.name,
		event = "resolveStat",
		tags = (self.config and self.config.tags) or nil,
		step = meta.step,
		metadata = meta,
		base = {
			stat = statType,
			value = baseValue,
		},
	}

	local result = SkillMediator.resolve(ctx)
	local values = result.values
	local resolved = values and values.value
	if typeof(resolved) == "number" then
		return resolved
	end
	return baseValue
end

-- Build a standard SkillQueryContext for resolving skill cost.
function BaseSkill:_buildCostContext(
	baseResource: any,
	baseAmount: number,
	extraMeta: { [string]: any }?
): SkillQueryTypes.SkillQueryContext
	local meta = cloneTable(extraMeta)
	meta.resource = baseResource
	meta.skill = self.name
	meta.skillId = self.id
	meta.skillCategory = self.config and self.config.category or nil
	meta.skillTags = self.config and (self.config.tags or self.config.categories) or nil
	meta.casterId = self.casterId

	return {
		entityId = self.casterId,
		skillId = self.name,
		event = "resolveSkillCost",
		tags = (self.config and self.config.tags) or nil,
		step = meta.step,
		metadata = meta,
		base = {
			resource = baseResource,
			amount = baseAmount,
		},
	}
end

function BaseSkill:resolveTiming()
	-- Simplified: timing service now infers tempo and durationScale from skill tags and entity stats.
	return SkillTimingService.resolve(self.casterId, self.name)
end

-- DEPRECATED: Cast sounds are now played client-side immediately via ImmediateHitFeedback
-- This method is kept for reference but should not be used.
-- Client-side approach: BaseSkill:playCastSoundLocal() in src/client/SkillsFramework/Skills/BaseSkill.luau
--[[
function BaseSkill:playCastSound()
	local castSounds = self.config and self.config.castSounds
	if not castSounds or type(castSounds) ~= "table" or #castSounds == 0 then
		return
	end
	local soundId = castSounds[math.random(1, #castSounds)]
	if not soundId or soundId == "" then
		return
	end
	local casterEntity = self.caster
	if not casterEntity then
		return
	end
	local position: Vector3
	if casterEntity:IsA("Model") then
		local hrp = casterEntity:FindFirstChild("HumanoidRootPart") :: BasePart?
		position = hrp and hrp.Position or casterEntity:GetPivot().Position
	elseif casterEntity:IsA("BasePart") then
		position = casterEntity.Position
	else
		return
	end
	dispatcher:emit("SkillCastSound", {
		skillId = self.id,
		soundId = soundId,
		position = position,
	})
end
]]

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
	local state = self._execState
	if state then
		for key, value in pairs(payload) do
			state[key] = value
		end
	end
end

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
	local timingInfo = data and data.timing
	local cost = self:getBaseCost(data)
	local baseResource = self.config and self.config.baseResource or StatTypes.PoolStats.Stamina

	if cost <= 0 then
		return true
	end

	local costMetadata = {
		step = comboConfig and comboConfig.step or nil,
	}
	if timingInfo then
		costMetadata.durationScale = timingInfo.durationScale
		if timingInfo.metadata then
			costMetadata.timingMetadata = timingInfo.metadata
		end
	end

	local ctx = self:_buildCostContext(baseResource, cost, costMetadata)
	local result = SkillMediator.resolve(ctx)
	local values = result.values
	local resolvedResource = (values and values.resource) or baseResource
	local resolvedAmount = (values and values.amount) or cost

	-- Check affordability using resolved values
	local preview = StatsManager.resolvePoolCost(self.casterId, resolvedResource, resolvedAmount, {
		metadata = ctx.metadata,
	})
	if not preview or (preview.currentValue + 1e-3 < preview.finalCost) then
		return false
	end

	StatsManager.removeFromPool(self.casterId, resolvedResource, resolvedAmount, {
		metadata = ctx.metadata,
	})
	return true
end

function BaseSkill:previewResourceCost(poolType: any, amount: number, metadata: { [any]: any }?, _overrides)
	local ctx = self:_buildCostContext(poolType, amount, metadata or {})
	local result = SkillMediator.resolve(ctx)
	local values = result.values
	local resolvedResource = (values and values.resource) or poolType
	local resolvedAmount = (values and values.amount) or amount
	local preview = StatsManager.resolvePoolCost(self.casterId, resolvedResource, resolvedAmount, {
		metadata = ctx.metadata,
	})
	if preview then
		preview.poolName = resolvedResource
		preview.finalCost = resolvedAmount
	end
	return preview
end

function BaseSkill:use()
	-- child should override
	error("BaseSkill:use() must be implemented by child: " .. tostring(self.name))
end

-- ============================================================================
-- ATTACK COMPOSITION SYSTEM
-- ============================================================================

-- Build an attack composition from base damage values
-- Uses SkillMediator resolver pipeline for modifier support
function BaseSkill:resolveAttack(base: {
	damage: number,
	damageType: string,
	[string]: any,
}): AttackTypes.AttackContext
	-- Build attack query context
	local queryCtx = {
		entityId = self.casterId,
		skillId = self.name,
		queryType = "resolveAttack",
		tags = self.config and self.config.tags or nil,
		step = base.comboStep,
		metadata = base.metadata,
		baseAttack = {
			damage = base.damage,
			damageType = base.damageType,
			effectId = base.effectId,
			effectChance = base.effectChance,
			comboStep = base.comboStep,
			isCrit = base.isCrit or false,
		},
	}

	-- Resolve through AttackResolver (will apply modifiers once registry exists)
	local result = AttackResolver.resolve(queryCtx)

	-- Convert query result to AttackContext
	return {
		packets = result.packets,
		sourceId = self.casterId,
		metadata = result.metadata or {
			skillId = self.name,
			tags = self.config and self.config.tags or nil,
			isCrit = base.isCrit or false,
			comboStep = base.comboStep,
		},
	}
end

-- Emit a start phase; children can override before/after
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
	attemptId: string?,
	sessionId: string?, -- Phase 3: Session ID from SkillsManager
}

-- Execution helpers: wrap emitStart/emitEnd with execution lock semantics.
-- duration: optional planned execution length (auto-completes). If nil, skill must call completeExecution manually.
function BaseSkill:beginExecution(duration: number?, opts: ExecutionOptions)
	if self._execToken then
		return
	end -- already executing

	-- Phase 3: Extract sessionId from opts (passed by SkillsManager)
	self._sessionId = opts.sessionId

	-- Compute tempo for execution state from timing.durationScale (tempo == 1/durationScale)
	local tempo = opts.speedMult or nil
	if
		tempo == nil
		and opts.timing
		and type(opts.timing.durationScale) == "number"
		and opts.timing.durationScale ~= 0
	then
		tempo = 1 / opts.timing.durationScale
	end

	local token = HttpService:GenerateGUID(false)
	local now = os.clock()
	local state = {
		skill = self.name,
		token = token,
		startedAt = now,
		plannedDuration = duration,
		targetDuration = duration,
		tempo = tempo,
		durationScale = opts.timing and opts.timing.durationScale or nil,
		timing = opts.timing,
		attemptId = opts.attemptId,
	}
	self._execToken = token
	self._execState = state
	if opts.timing then
		self:_captureTiming(opts.timing)
	end

	-- Auto-complete if a duration is provided (mirrors previous ExecutionService behavior)
	if duration and duration > 0 then
		local capturedToken = token
		self._autoCompleteToken = capturedToken
		task.delay(duration, function()
			if self._execToken == capturedToken then
				self:completeExecution("auto")
			end
		end)
	end

	-- Phase 3: Transition session to ACTIVE
	if self._sessionId then
		local success = SessionManager.transition(self._sessionId, "ACTIVE", "execution_started")
		debugPhase3("Session transition to ACTIVE:", self._sessionId:sub(1, 8), "success=", success)
	end

	return true
end

function BaseSkill:completeExecution(reason: string?)
	debugPhase3(
		`completeExecution called for {self.name}, reason: {reason or "nil"}, _execToken: {self._execToken or "nil"}`
	)
	if not self._execToken then
		debugPhase3(`EARLY EXIT: No _execToken for {self.name}`)
		return
	end
	local state = self._execState
	local sessionId = self._sessionId
	self._execToken = nil
	self._execState = nil
	self._sessionId = nil
	self._autoCompleteToken = nil

	-- Phase 3: Transition session to COMPLETED
	if sessionId then
		local success = SessionManager.transition(sessionId, "COMPLETED", reason or "execution_completed")
		debugPhase3("Session transition to COMPLETED:", sessionId:sub(1, 8), "success=", success)
	end

	local finishedAt = os.clock()
	local startedAt = state and state.startedAt or nil
	local elapsed = nil
	if startedAt then
		elapsed = math.max(0, finishedAt - startedAt)
	end
	local timing = self._lastTiming
	local durationScale = state and state.durationScale or (timing and timing.durationScale)
	local tempo = state and state.tempo or (durationScale and durationScale ~= 0 and 1 / durationScale) or nil
	local _endData = {
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
		_endData.duration = state.plannedDuration
	end
	self._lastTiming = nil
end

function BaseSkill:onSessionEnded(sessionId: string, newState: string, reason: string?)
	if self._sessionId ~= sessionId then
		return
	end
	if not self._execToken then
		self._sessionId = nil
		self._autoCompleteToken = nil
		self._lastTiming = nil
		return
	end
	self._execToken = nil
	self._execState = nil
	self._sessionId = nil
	self._autoCompleteToken = nil
	self._lastTiming = nil
	debugPhase3(
		"Cleared local execution for",
		self.name,
		"session",
		sessionId:sub(1, 8),
		"state=",
		newState,
		"reason=",
		reason or "none"
	)
end

function BaseSkill:getCasterModel(): Model?
	if self.caster:IsA("Model") then
		return self.caster
	end
	return self.caster:FindFirstAncestorOfClass("Model")
end

function BaseSkill:getCasterRootPart(): BasePart?
	if self.caster then
		return self.caster:FindFirstChild("HumanoidRootPart") :: BasePart?
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
