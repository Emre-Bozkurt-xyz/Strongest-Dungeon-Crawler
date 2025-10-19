--!strict
local NPCManager = require(script.Parent.Parent.NPCManager)
local Movement = require(script.Parent.Movement)
local Combat = require(script.Parent.Combat)
local Damageable = require(script.Parent.Damageable)
local BehaviorToolkit = require(script.Parent.Parent.BehaviorToolkit)

type BehaviorContext = {
	behavior: any,
	movement: any?,
	combat: any?,
	damageable: any?,
	model: Model,
	now: number,
	deltaTime: number,
	memory: { [string]: any },
	config: { [string]: any },
}

type BehaviorAction = (BehaviorContext) -> ()
type BehaviorTransition = {
	to: string,
	when: (BehaviorContext) -> boolean,
	actions: { BehaviorAction }?,
	debugLabel: string?,
}

type BehaviorStateSpec = {
	onEnter: { BehaviorAction }?,
	onExit: { BehaviorAction }?,
	onTick: { BehaviorAction }?,
	transitions: { BehaviorTransition }?,
}

type BehaviorGraph = {
	initialState: string,
	states: { [string]: BehaviorStateSpec },
}

export type BehaviorConfig = {
	thinkInterval: number?,
	enablePatrol: boolean?,
	leashRadius: number?,
	maxChaseDistance: number?,
	repathDistance: number?,
	repathInterval: number?,
	chaseHysteresis: number?,
	returnHomeResumeDistance: number?,
	idleHoldMin: number?,
	idleHoldMax: number?,
	fleeHealthThreshold: number?,
	resumeHealthThreshold: number?,
	graph: BehaviorGraph?,
	globalTransitions: { BehaviorTransition }?,
	debugReturnHome: boolean?,
	debugStateTransitions: boolean?,
}

type BehaviorMemory = {
	spawnPosition: Vector3,
	idleHoldUntil: number,
	lastPathGoal: Vector3?,
	lastPathTime: number,
	returningHome: boolean,
}

local Defaults = BehaviorToolkit.Defaults

local Behavior = {}
Behavior.__index = Behavior

local _Registry: { [Model]: any } = {}

local DEBUG_PREFIX = "[BehaviorDebug]"

local function logDebugReturnHome(self: any, message: string)
	if not self.config.debugReturnHome then
		return
	end
	print(string.format("%s[%s] %s", DEBUG_PREFIX, self.model.Name, message))
end

local function logDebugTransition(self: any, message: string)
	if not self.config.debugStateTransitions then
		return
	end
	print(string.format("%s[%s][State] %s", DEBUG_PREFIX, self.model.Name, message))
end

local function resolveSpawnPosition(model: Model): Vector3
	local primary = model.PrimaryPart
	if primary then
		return primary.Position
	end
	return model:GetPivot().Position
end

local function copyConfig(config: BehaviorConfig?): { [string]: any }
	if not config then
		return {}
	end
	return table.clone(config)
end

local function hydrateConfig(config: BehaviorConfig?): { [string]: any }
	local source = copyConfig(config)
	if not source.graph then
		source = Defaults.basic(source)
	end
	source.thinkInterval = source.thinkInterval or 0.25
	source.enablePatrol = if source.enablePatrol ~= nil then source.enablePatrol else true
	source.leashRadius = source.leashRadius or 32
	source.maxChaseDistance = source.maxChaseDistance or 48
	source.repathDistance = source.repathDistance or 6
	source.repathInterval = source.repathInterval or 1.0
	source.chaseHysteresis = source.chaseHysteresis or 3
	source.returnHomeResumeDistance = source.returnHomeResumeDistance or math.max(0, (source.leashRadius or 32) * 0.6)
	source.idleHoldMin = source.idleHoldMin or 1
	source.idleHoldMax = source.idleHoldMax or 4
	source.fleeHealthThreshold = source.fleeHealthThreshold or 0.15
	source.resumeHealthThreshold = source.resumeHealthThreshold or 0.4
	source.globalTransitions = source.globalTransitions or {}
	source.debugReturnHome = source.debugReturnHome == true
	source.debugStateTransitions = source.debugStateTransitions == true
	return source
end

local function randomDuration(rand: Random, minValue: number, maxValue: number): number
	if maxValue <= minValue then
		return minValue
	end
	return minValue + rand:NextNumber() * (maxValue - minValue)
end

local function registerInstance(model: Model, instance: any)
	_Registry[model] = instance
	model.Destroying:Connect(function()
		_Registry[model] = nil
	end)
end

function Behavior.new(npcModel: Model, config: BehaviorConfig?): any
	local component = NPCManager.addComponent(npcModel, "Behavior")
	local resolvedConfig = hydrateConfig(config)
	local spawnPosition = resolveSpawnPosition(npcModel)
	local now = os.clock()
	local memory: BehaviorMemory = {
		spawnPosition = spawnPosition,
		idleHoldUntil = now,
		lastPathGoal = nil,
		lastPathTime = 0,
		returningHome = false,
	}
	local self = setmetatable({
		model = npcModel,
		component = component,
		config = resolvedConfig,
		graph = resolvedConfig.graph,
		globalTransitions = resolvedConfig.globalTransitions,
		memory = memory,
		random = Random.new(),
		state = resolvedConfig.graph.initialState,
		stateChangedAt = now,
		lastThink = 0,
	}, Behavior)

	component:SetAttribute("State", self.state)
	component:SetAttribute("StateChangedAt", now)
	component:SetAttribute("SpawnPosition", spawnPosition)
	component:SetAttribute("ThinkInterval", resolvedConfig.thinkInterval)
	component:SetAttribute("ConfigEnablePatrol", resolvedConfig.enablePatrol)
	component:SetAttribute("ConfigLeashRadius", resolvedConfig.leashRadius)
	component:SetAttribute("ConfigMaxChaseDistance", resolvedConfig.maxChaseDistance)
	component:SetAttribute("ConfigChaseHysteresis", resolvedConfig.chaseHysteresis)
	component:SetAttribute("ConfigFleeThreshold", resolvedConfig.fleeHealthThreshold)
	component:SetAttribute("ConfigResumeThreshold", resolvedConfig.resumeHealthThreshold)
	component:SetAttribute("ConfigReturnHomeResumeDistance", resolvedConfig.returnHomeResumeDistance)
	component:SetAttribute("ReturningHome", false)
	component:SetAttribute("DebugReturnHome", resolvedConfig.debugReturnHome)
	component:SetAttribute("DebugStateTransitions", resolvedConfig.debugStateTransitions)

	self:scheduleIdleHold(nil)
	registerInstance(npcModel, self)
	return self
end

function Behavior.get(npcModel: Model): any
	return _Registry[npcModel]
end

function Behavior:getState(): string
	return self.state
end

function Behavior:timeInState(now: number): number
	return now - self.stateChangedAt
end

function Behavior:getPosition(): Vector3
	local root = self.model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		return root.Position
	end
	return self.memory.spawnPosition
end

function Behavior:distanceFromSpawn(): number
	return (self:getPosition() - self.memory.spawnPosition).Magnitude
end

function Behavior:getHealthFraction(): number
	local damageable = Damageable.get(self.model)
	if not damageable then
		return 1
	end
	local maxHealth = damageable:getMaxHealth()
	if maxHealth <= 0 then
		return 1
	end
	return damageable:getHealth() / maxHealth
end

function Behavior:isDead(): boolean
	local damageable = Damageable.get(self.model)
	return damageable ~= nil and damageable:getHealth() <= 0
end

function Behavior:hasTarget(): boolean
	local combat = Combat.get(self.model)
	if not combat then
		return false
	end
	return combat:getTarget() ~= nil
end

function Behavior:isTargetWithinAttackRange(): boolean
	local combat = Combat.get(self.model)
	if not combat then
		return false
	end
	return combat:isTargetInRange()
end

function Behavior:isTargetWithinDistance(distance: number): boolean
	local combat = Combat.get(self.model)
	if not combat then
		return false
	end
	local dist = combat:getDistanceToTarget()
	return dist <= distance
end

function Behavior:isIdleHoldExpired(now: number): boolean
	return now >= self.memory.idleHoldUntil
end

function Behavior:stopMovement(ctx: BehaviorContext?)
	local movement = (ctx and ctx.movement) or Movement.get(self.model)
	if movement then
		movement:stop()
	end
end

function Behavior:enableWalking(ctx: BehaviorContext?)
	local movement = (ctx and ctx.movement) or Movement.get(self.model)
	if movement then
		movement:enableWalking()
	end
end

function Behavior:enableRunning(ctx: BehaviorContext?)
	local movement = (ctx and ctx.movement) or Movement.get(self.model)
	if movement then
		movement:enableRunning()
	end
end

function Behavior:startPatrol(ctx: BehaviorContext?)
	local movement = (ctx and ctx.movement) or Movement.get(self.model)
	if not movement then
		return
	end
	movement:enableWalking()
	movement:startPatrolling()
end

function Behavior:continuePatrol(ctx: BehaviorContext?)
	local movement = (ctx and ctx.movement) or Movement.get(self.model)
	if not movement then
		return
	end
	if movement:getState() ~= "patrolling" then
		movement:startPatrolling()
	end
end

function Behavior:scheduleIdleHold(ctx: BehaviorContext?)
	local now = ctx and ctx.now or os.clock()
	local duration = randomDuration(self.random, self.config.idleHoldMin, self.config.idleHoldMax)
	self.memory.idleHoldUntil = now + duration
	self.component:SetAttribute("IdleHoldUntil", self.memory.idleHoldUntil)
end

function Behavior:markReturningHome(_ctx: BehaviorContext?)
	if self.memory.returningHome then
		return
	end
	self.memory.returningHome = true
	self.component:SetAttribute("ReturningHome", true)
	logDebugReturnHome(self, string.format("Entering returning-home; distance=%.2f", self:distanceFromSpawn()))
end

function Behavior:clearReturningHome(_ctx: BehaviorContext?)
	if not self.memory.returningHome then
		return
	end
	self.memory.returningHome = false
	self.component:SetAttribute("ReturningHome", false)
	logDebugReturnHome(self, string.format("Exiting returning-home; distance=%.2f", self:distanceFromSpawn()))
end

function Behavior:isReturningHome(): boolean
	return self.memory.returningHome
end

function Behavior:pathHomeIfReturning(ctx: BehaviorContext?)
	if not self.memory.returningHome then
		return
	end
	self:pathToSpawn(ctx)
end

function Behavior:acquireTarget(ctx: BehaviorContext?)
	local combat = (ctx and ctx.combat) or Combat.get(self.model)
	if not combat then
		return
	end
	if self.memory.returningHome then
		local resumeDistance = self.config.returnHomeResumeDistance or 0
		local distance = self:distanceFromSpawn()
		if resumeDistance > 0 and distance > resumeDistance then
			logDebugReturnHome(self, string.format(
				"Suppressing target acquisition while returning home; distance=%.2f resume<=%.2f",
				distance,
				resumeDistance
			))
			return
		end
		logDebugReturnHome(self, string.format("Resuming target acquisition; distance=%.2f", distance))
		self:clearReturningHome(ctx)
	end
	local target = combat:getTarget()
	if target and target.Parent then
		return
	end
	local closest = combat:findClosestEnemy()
	if closest then
		combat:setTarget(closest)
	end
end

function Behavior:clearTarget(ctx: BehaviorContext?)
	local combat = (ctx and ctx.combat) or Combat.get(self.model)
	if combat then
		combat:setTarget(nil)
	end
	self.memory.lastPathGoal = nil
end

function Behavior:attemptAttack(ctx: BehaviorContext?)
	local combat = (ctx and ctx.combat) or Combat.get(self.model)
	if not combat or not combat:getTarget() then
		return
	end
	if combat:canAttack() then
		task.spawn(function()
			combat:attack()
		end)
	end
end

function Behavior:pathToTarget(ctx: BehaviorContext?)
	local combat = (ctx and ctx.combat) or Combat.get(self.model)
	local movement = (ctx and ctx.movement) or Movement.get(self.model)
	if not combat or not movement then
		return
	end
	local target = combat:getTarget()
	if not target then
		return
	end
	local goal = combat:getTargetPosition(target)
	self:_maybePathTo(movement, goal, ctx and ctx.now or os.clock())
end

function Behavior:pathToSpawn(ctx: BehaviorContext?)
	local movement = (ctx and ctx.movement) or Movement.get(self.model)
	if not movement then
		return
	end
	self:_maybePathTo(movement, self.memory.spawnPosition, ctx and ctx.now or os.clock())
end

function Behavior:_maybePathTo(movement: any, goal: Vector3, now: number)
	local lastGoal = self.memory.lastPathGoal
	local lastTime = self.memory.lastPathTime
	local distanceThreshold = self.config.repathDistance
	local intervalThreshold = self.config.repathInterval
	local needsGoalRefresh = not lastGoal or (goal - lastGoal).Magnitude >= distanceThreshold
	if needsGoalRefresh or (now - lastTime) >= intervalThreshold then
		movement:pathfindTo(goal)
		self.memory.lastPathGoal = goal
		self.memory.lastPathTime = now
		self.component:SetAttribute("LastPathGoal", goal)
		self.component:SetAttribute("LastPathTime", now)
		if self.memory.returningHome and (goal - self.memory.spawnPosition).Magnitude < 1e-3 then
			logDebugReturnHome(self, string.format(
				"Issued pathfind home; delta=%.2f dt=%.2f threshold=%.2f",
				lastGoal and (goal - lastGoal).Magnitude or -1,
				now - lastTime,
				intervalThreshold
			))
		end
	elseif self.memory.returningHome then
		local goalDelta = lastGoal and (goal - lastGoal).Magnitude or -1
		logDebugReturnHome(self, string.format(
			"Skipped pathfind; delta=%.2f dt=%.2f threshold=%.2f",
			goalDelta,
			now - lastTime,
			intervalThreshold
		))
	end
end

local function buildContext(self: any, now: number, deltaTime: number): BehaviorContext?
	local movement = Movement.get(self.model)
	local combat = Combat.get(self.model)
	if not movement or not combat then
		return nil
	end
	local damageable = Damageable.get(self.model)
	return {
		behavior = self,
		movement = movement,
		combat = combat,
		damageable = damageable,
		model = self.model,
		now = now,
		deltaTime = deltaTime,
		memory = self.memory,
		config = self.config,
	}
end

function Behavior:_shouldThink(now: number): boolean
	if now - self.lastThink < self.config.thinkInterval then
		return false
	end
	self.lastThink = now
	self.component:SetAttribute("LastThink", now)
	return true
end

local function runActions(actions: { BehaviorAction }?, context: BehaviorContext)
	if not actions then
		return
	end
	for _, action in ipairs(actions) do
		local ok, err = pcall(function()
			(action :: any)(context)
		end)
		if not ok then
			warn("Behavior action error", err)
		end
	end
end

function Behavior:_setState(newState: string, now: number)
	if self.state ~= newState then
		local prevState = self.state
		local timeInPrev = now - self.stateChangedAt
		logDebugTransition(self, string.format("%s -> %s (%.2fs)", prevState, newState, timeInPrev))
	end
	self.state = newState
	self.stateChangedAt = now
	self.component:SetAttribute("State", newState)
	self.component:SetAttribute("StateChangedAt", now)
end

function Behavior:_applyTransitions(transitions: { BehaviorTransition }?, context: BehaviorContext, now: number): boolean
	if not transitions then
		return false
	end
	for _, transition in ipairs(transitions) do
		local predicate = transition.when
		local shouldMove = predicate == nil or predicate(context)
		if shouldMove then
			local currentStateSpec = self.graph.states[self.state]
			runActions(currentStateSpec and currentStateSpec.onExit, context)
			runActions(transition.actions, context)
			if transition.debugLabel then
				logDebugTransition(self, string.format("Transition trigger: %s", transition.debugLabel))
			end
			self:_setState(transition.to, now)
			runActions(self.graph.states[self.state] and self.graph.states[self.state].onEnter, context)
			return true
		end
	end
	return false
end

function Behavior:update(deltaTime: number)
	local now = os.clock()
	if not self:_shouldThink(now) then
		return
	end
	local context = buildContext(self, now, deltaTime)
	if not context then
		return
	end
	local transitioned = self:_applyTransitions(self.globalTransitions, context, now)
	if transitioned then
		context = buildContext(self, now, deltaTime)
		if not context then
			return
		end
	end
	local iteration = 0
	while iteration < 4 do
		iteration += 1
		local stateSpec = self.graph.states[self.state]
		if not stateSpec then
			break
		end
		if self:_applyTransitions(stateSpec.transitions, context, now) then
			context = buildContext(self, now, deltaTime)
			if not context then
				return
			end
		else
			runActions(stateSpec.onTick, context)
			break
		end
	end
end

function Behavior.updateAll(deltaTime: number)
	for model, instance in pairs(_Registry) do
		if model.Parent then
			instance:update(deltaTime)
		else
			_Registry[model] = nil
		end
	end
end

return Behavior
