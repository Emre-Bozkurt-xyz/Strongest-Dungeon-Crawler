--!strict
-- Combat Component: Handles NPC combat abilities, targeting, and attack patterns

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NPCManager = require(script.Parent.Parent.NPCManager)
local StatsManager = require(script.Parent.Parent.Parent.StatsManager)
local StatTypes = require(ReplicatedStorage.Shared.StatTypes)
local NPCAnimationController = require(script.Parent.Parent.NPCAnimationController)
local SkillsManager = require(script.Parent.Parent.Parent.SkillsFramework.SkillsManager)
local SkillsConfig = require(script.Parent.Parent.Parent.SkillsFramework.SkillsConfig)
local ExecutionService = require(script.Parent.Parent.Parent.SkillsFramework.ExecutionService)

type SkillData = SkillsConfig.SkillData
type ComboData = {
	steps: number,
	window: number,
	stepDelays: { number }?,
	hitDelays: { number }?,
	recovery: number?,
	comboCooldown: number?,
}

local Combat = {}
Combat.__index = Combat

-- Static registry for Combat components
local _Registry: { [Model]: boolean } = {}
local function _register(model: Model)
	_Registry[model] = true
	model.Destroying:Connect(function()
		_Registry[model] = nil
		SkillsManager.removeAll(model)
	end)
end

local function _collectSkillConfigs(model: Model, component: any?): { [string]: SkillData }
	local configs: { [string]: SkillData } = {}
	local comp = component or NPCManager.getComponent(model, "Combat")
	if not comp then
		return configs
	end
	local countAttr = comp:GetAttribute("skillCount")
	local count = if typeof(countAttr) == "number" then countAttr else 0
	for index = 1, count do
		local skillName = comp:GetAttribute("skill_" .. index) :: string?
		if skillName then
			local cfg = SkillsManager.getSkillConfig(model, skillName)
			configs[skillName] = cfg or SkillsConfig.skills[skillName]
		end
	end
	return configs
end

ExecutionService.onCompleted(function(caster: Instance, _skill: string, _reason: string)
	if not caster:IsA("Model") then
		return
	end

	local model = caster :: Model
	if not _Registry[model] then
		return
	end

	if model:GetAttribute("CombatState") == "attacking" then
		model:SetAttribute("CombatState", "aggressive")
	end

	local component = NPCManager.getComponent(model, "Combat")
	if component then
		component:SetAttribute("lastAttackTime", os.clock())
	end
end)

export type CombatConfig = {
	damage: number?,
	attackRange: number?,
	attackCooldown: number?,
	skills: { string }?, -- Array of skill names the NPC can use
	aggroRange: number?, -- How far NPC can detect enemies
	attackPattern: string?, -- "basic", "combo", "ranged", etc.
	skillOverrides: { [string]: SkillsConfig.SkillConfigOverride }?,
}

export type CombatState = "passive" | "aggressive" | "attacking" | "cooldown" | "fleeing"

-- Create a Combat component for an NPC
function Combat.new(npcModel: Model, config: CombatConfig): any
	local component = NPCManager.addComponent(npcModel, "Combat")
	
	-- Set up combat attributes
	npcModel:SetAttribute("BaseDamage", config.damage or 10)
	npcModel:SetAttribute("AttackRange", config.attackRange or 5)
	npcModel:SetAttribute("AttackCooldown", config.attackCooldown or 2)
	npcModel:SetAttribute("AggroRange", config.aggroRange or 15)
	npcModel:SetAttribute("AttackPattern", config.attackPattern or "basic")
	
	-- Combat state tracking
	npcModel:SetAttribute("CombatState", "passive")
	component:SetAttribute("currentTarget", "")
	component:SetAttribute("lastAttackTime", 0)
	component:SetAttribute("aggroTime", 0)
	
	-- Store skills and register them with the shared skill system
	local configuredSkills = {}
	if config.skills and #config.skills > 0 then
		for _, skillName in ipairs(config.skills) do
			table.insert(configuredSkills, skillName)
		end
	elseif SkillsConfig.skills.SinglePunch ~= nil then
		table.insert(configuredSkills, "SinglePunch")
	elseif SkillsConfig.skills.Punch ~= nil then
		table.insert(configuredSkills, "Punch")
	end

	local existingCount = component:GetAttribute("skillCount")
	local previousCount = if typeof(existingCount) == "number" then existingCount else 0

	SkillsManager.removeAll(npcModel)
	local registeredSkills = {}
	for _, skillName in ipairs(configuredSkills) do
		local override = if config.skillOverrides then config.skillOverrides[skillName] else nil
		local ok, result = pcall(SkillsManager.addSkill, npcModel, skillName, override)
		if ok and result ~= nil then
			table.insert(registeredSkills, skillName)
		else
			local errMessage = if ok then "unknown_error" else tostring(result)
			warn(`Combat: failed to register skill '{skillName}' for {npcModel.Name}: {errMessage}`)
		end
	end

	component:SetAttribute("skillCount", #registeredSkills)
	for i, skillName in ipairs(registeredSkills) do
		component:SetAttribute("skill_" .. i, skillName)
	end
	for j = #registeredSkills + 1, previousCount do
		component:SetAttribute("skill_" .. j, nil)
	end

	-- Initialize stats for this NPC if not already registered
	local stats = StatsManager.register(npcModel)
	local baseDamage = config.damage or 10
	local damageStat = stats[StatTypes.StaticStats.PhysicalDamage]
	if damageStat and damageStat.setBaseValue then
		damageStat:setBaseValue(baseDamage)
	else
		npcModel:SetAttribute("BaseDamage", baseDamage)
	end
	
	local self = setmetatable({
		model = npcModel,
		component = component,
		target = nil,
		skillConfigs = _collectSkillConfigs(npcModel, component),
	}, Combat)

	_register(npcModel)
	return self
end

-- Get Combat component from an NPC model
function Combat.get(npcModel: Model): any?
	if not NPCManager.hasComponent(npcModel, "Combat") then
		return nil
	end
	
	local component = NPCManager.getComponent(npcModel, "Combat")
	if not component then return nil end
	
	return setmetatable({
		model = npcModel,
		component = component,
		target = nil,
		skillConfigs = _collectSkillConfigs(npcModel, component),
	}, Combat)
end

-- Get current combat state
function Combat:getState(): CombatState
	return self.model:GetAttribute("CombatState") or "passive"
end

-- Set combat state
function Combat:setState(state: CombatState)
	self.model:SetAttribute("CombatState", state)
end

-- Get current target
function Combat:getTarget(): Model?
	local targetName = self.component:GetAttribute("currentTarget") :: string?
	if not targetName or targetName == "" then return nil end
	
	-- Try to find target in workspace (could be player or another NPC)
	for _, player in pairs(game.Players:GetPlayers()) do
		if player.Name == targetName and player.Character then
			return player.Character
		end
	end
	
	return nil
end

-- Set target
function Combat:setTarget(target: Model?)
	if target then
		self.component:SetAttribute("currentTarget", target.Name)
		if self:getState() == "passive" then
			self:setState("aggressive")
			self.component:SetAttribute("aggroTime", os.clock())
		end
	else
		self.component:SetAttribute("currentTarget", "")
		if self:getState() ~= "passive" then
			self:setState("passive")
		end
	end
	self.target = target
end

-- Check if target is in range
function Combat:isTargetInRange(range: number?): boolean
	local target = self:getTarget()
	if not target then return false end
	
	local checkRange = range or self.model:GetAttribute("AttackRange") or 5
	local distance = self:getDistanceToTarget()
	return distance <= checkRange
end

-- Get distance to current target
function Combat:getDistanceToTarget(): number
	local target = self:getTarget()
	if not target then return math.huge end
	
	local myPos = self:getPosition()
	local targetPos = self:getTargetPosition(target)
	return (myPos - targetPos).Magnitude
end

-- Get NPC position
function Combat:getPosition(): Vector3
	local humanoidRootPart = self.model:FindFirstChild("HumanoidRootPart") :: BasePart?
	return humanoidRootPart and humanoidRootPart.Position or Vector3.new(0, 0, 0)
end

-- Get target position
function Combat:getTargetPosition(target: Model): Vector3
	local targetRoot = target:FindFirstChild("HumanoidRootPart") :: BasePart?
	return targetRoot and targetRoot.Position or Vector3.new(0, 0, 0)
end

-- Find nearby enemies within aggro range
function Combat:findNearbyEnemies(): { Model }
	local enemies = {}
	local myPos = self:getPosition()
	local aggroRange = self.model:GetAttribute("AggroRange") or 15
	
	-- Check all players
	for _, player in pairs(game.Players:GetPlayers()) do
		if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
			local distance = (myPos - player.Character.HumanoidRootPart.Position).Magnitude
			if distance <= aggroRange then
				table.insert(enemies, player.Character)
			end
		end
	end
	
	-- Could also check other NPCs with different factions here
	
	return enemies
end

-- Find closest enemy
function Combat:findClosestEnemy(): Model?
	local enemies = self:findNearbyEnemies()
	if #enemies == 0 then return nil end
	
	local myPos = self:getPosition()
	local closest = nil
	local closestDistance = math.huge
	
	for _, enemy in ipairs(enemies) do
		local distance = (myPos - self:getTargetPosition(enemy)).Magnitude
		if distance < closestDistance then
			closest = enemy
			closestDistance = distance
		end
	end
	
	return closest
end

-- Check if attack is ready (not on cooldown)
function Combat:canAttack(): boolean
	local locked = ExecutionService.isLocked(self.model)
	if locked then
		return false
	end
	local lastAttack = self.component:GetAttribute("lastAttackTime") or 0
	local cooldown = self.model:GetAttribute("AttackCooldown") or 2
	return (os.clock() - lastAttack) >= cooldown
end

-- Perform basic attack
function Combat:attack(): boolean
	if not self:canAttack() then
		return false
	end

	local target = self:getTarget()
	if not target or not self:isTargetInRange() then
		return false
	end

	self.component:SetAttribute("lastAttackTime", os.clock())
	self:setState("attacking")

	local skillName = self:_selectSkill()
	self:_playSkillAnimation(skillName)

	if skillName and self:_getSkillConfig(skillName) then
		self:_executeSkill(skillName)
		return true
	end

	-- Fallback path: direct damage if no skill configured or registration failed
	local damage = self:_getBaseDamage()
	self:_applyDamageToTarget(target, damage)
	self:_scheduleAggressiveFallback(0.5)
	return true
end

-- Use a specific skill 
function Combat:useSkill(skillName: string): boolean
	if not self:canAttack() then
		return false
	end

	local target = self:getTarget()
	if not target then
		return false
	end

	self.component:SetAttribute("lastAttackTime", os.clock())
	self:setState("attacking")
	self:_playSkillAnimation(skillName)

	if self:_getSkillConfig(skillName) then
		self:_executeSkill(skillName)
	else
		SkillsManager.useSkill(self.model, skillName, self:_buildSkillRequestData(target))
		self:_scheduleAggressiveFallback(0.5)
	end

	return true
end

function Combat:_selectSkill(): string?
	local skills = self:getSkills()
	if #skills == 0 then
		return nil
	end
	return skills[1]
end

function Combat:_ensureSkillConfigCache()
	if not self.skillConfigs then
		self.skillConfigs = _collectSkillConfigs(self.model, self.component)
	end
end

function Combat:_getSkillConfig(skillName: string): SkillData?
	self:_ensureSkillConfigCache()
	if not skillName then
		return nil
	end
	local cfg = self.skillConfigs[skillName]
	if cfg then
		return cfg
	end
	local runtimeCfg = SkillsManager.getSkillConfig(self.model, skillName)
	if runtimeCfg then
		self.skillConfigs[skillName] = runtimeCfg
		return runtimeCfg
	end
	return SkillsConfig.skills[skillName]
end

function Combat:_playSkillAnimation(skillName: string?)
	local toPlay = skillName
	if not toPlay then
		local skills = self:getSkills()
		toPlay = skills[1]
	end
	if toPlay then
		NPCAnimationController.onSkillStart(self.model, toPlay)
	else
		NPCAnimationController.onSkillStart(self.model, "Punch")
	end
end

function Combat:_executeSkill(skillName: string)
	local skillConfig: SkillData? = self:_getSkillConfig(skillName)
	if skillConfig and skillConfig.combo then
		self:_autoComboSequence(skillName, skillConfig.combo, 1)
	else
		SkillsManager.useSkill(self.model, skillName, self:_buildSkillRequestData(self:getTarget()))
	end

	local fallbackDuration = self:_estimateSkillDuration(skillConfig)
	self:_scheduleAggressiveFallback(fallbackDuration)
end

function Combat:_autoComboSequence(skillName: string, comboConfig: ComboData?, step: number)
	if not comboConfig then
		return
	end
	if not self:_shouldContinueAttack() then
		return
	end

	SkillsManager.useSkill(self.model, skillName, self:_buildSkillRequestData(self:getTarget()))

	local totalSteps = comboConfig.steps or 1
	if step >= totalSteps then
		return
	end

	local delay = 0
	if comboConfig.stepDelays then
		delay = comboConfig.stepDelays[step] or 0
	end
	-- small epsilon keeps us safely past the per-step gating threshold
	delay = math.max(delay, 0) + 0.02

	task.delay(delay, function()
		if not self:_shouldContinueAttack() then
			return
		end
		self:_autoComboSequence(skillName, comboConfig, step + 1)
	end)
end

function Combat:_scheduleAggressiveFallback(duration: number)
	local delay = math.max(duration or 0, 0)
	if delay <= 0 then
		delay = 0.25
	end
	delay += 0.05

	task.delay(delay, function()
		if not self.model.Parent then
			return
		end
		if self:getState() == "attacking" then
			self:setState("aggressive")
		end
	end)
end

function Combat:_shouldContinueAttack(): boolean
	if not self.model.Parent then
		return false
	end
	return self:getState() == "attacking"
end

function Combat:_buildSkillRequestData(target: Model?): { [string]: any }
	local data = {}
	if target then
		data.targetName = target.Name
		local root = target:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			data.targetPosition = root.Position
		end
	end
	return data
end

function Combat:_estimateSkillDuration(skillConfig: SkillData?): number
	if not skillConfig then
		return 0.75
	end

	local minimum = 0.75

	if skillConfig.combo then
		local total = 0
		local steps = skillConfig.combo.steps or 1
		local stepDelays = skillConfig.combo.stepDelays
		if stepDelays then
			for i = 1, math.max(steps - 1, 0) do
				total += stepDelays[i] or 0
			end
		end
		local hitDelays = skillConfig.combo.hitDelays
		if hitDelays then
			total += hitDelays[steps] or 0
		end
		total += skillConfig.combo.recovery or 0
		return math.max(total, minimum)
	end

	if skillConfig.hits then
		local maxT = 0
		for _, hit in ipairs(skillConfig.hits) do
			if hit.t and hit.t > maxT then
				maxT = hit.t
			end
		end
		return math.max(maxT, minimum)
	end

	return minimum
end

-- Get available skills
function Combat:getSkills(): { string }
	local skills = {}
	local skillCount = self.component:GetAttribute("skillCount") or 0
	
	for i = 1, skillCount do
		local skillName = self.component:GetAttribute("skill_" .. i) :: string?
		if skillName then
			table.insert(skills, skillName)
		end
	end
	
	return skills
end

-- Private: Apply damage to target
function Combat:_applyDamageToTarget(target: Model, damage: number)
-- Always use CombatService to apply damage, regardless of target type
	local CombatService = require(script.Parent.Parent.Parent.CombatService)
	CombatService.applyDamage(target, damage, self.model)
	print(`{self.model.Name} dealt {damage} damage to {target.Name}`)
end

function Combat:_getBaseDamage(): number
	local stats = StatsManager.getAllStats(self.model)
	if stats then
		local damageStat = stats[StatTypes.StaticStats.PhysicalDamage]
		if damageStat and damageStat.getValue then
			return damageStat:getValue(stats)
		end
	end
	return self.model:GetAttribute("BaseDamage") or 10
end

-- Update combat behavior
function Combat:update(_deltaTime: number)
	local currentState = self:getState()

	if NPCManager.hasComponent(self.model, "Behavior") then
		local target = self:getTarget()
		if target and currentState == "passive" then
			self:setState("aggressive")
		elseif not target and currentState ~= "passive" then
			self:setState("passive")
		end
		return
	end
	
	if currentState == "passive" then
		-- Look for enemies to aggro
		local enemy = self:findClosestEnemy()
		if enemy then
			self:setTarget(enemy)
		end
	elseif currentState == "aggressive" then
		local target = self:getTarget()
		if not target then
			self:setState("passive")
			return
		end
		
		-- Check if target is too far away (lost aggro)
		local aggroRange = self.model:GetAttribute("AggroRange") or 15
		if self:getDistanceToTarget() > aggroRange * 1.2 then -- 20% buffer
			self:setTarget(nil)
			return
		end
		
		-- Try to attack if in range
		if self:isTargetInRange() and self:canAttack() then
			self:attack()
		end
	end
end

-- Static method: Update all NPCs with Combat components
function Combat.updateAll(deltaTime: number)
	for model in pairs(_Registry) do
		if model.Parent then
			local combat = Combat.get(model)
			if combat then
				combat:update(deltaTime)
			else
				_Registry[model] = nil
			end
		else
			_Registry[model] = nil
		end
	end
end

return Combat