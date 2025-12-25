--!strict
-- Stagger System - Server-side stagger application based on damage thresholds
-- Uses CharacterSpecs to determine when entities should be staggered
-- Called directly by CombatService before broadcasting HitEvent

local ServerScriptService = game:GetService("ServerScriptService")
local Server = ServerScriptService.Server

local StatusEffectsService = require(Server.StatusEffects.StatusEffectsService)
local StaggerCalculator = require(script.Parent.StaggerCalculator)

local StaggerSystem = {}

-- Track last stagger time per entity (for cooldown enforcement)
local lastStaggerTime: { [string]: number } = {}

-- Check if entity should be staggered based on damage and dynamic thresholds
local function shouldStagger(targetId: string, damage: number, specId: string?): boolean
	-- Compute dynamic stagger values based on current stats
	local staggerValues = StaggerCalculator.computeAll(targetId, specId)

	-- Check if on cooldown
	local now = os.clock()
	local lastStagger = lastStaggerTime[targetId] or 0
	if now - lastStagger < staggerValues.cooldown then
		return false
	end

	-- Check damage threshold
	if damage >= staggerValues.maxStackDamage then
		-- Guaranteed stagger on massive hits
		return true
	elseif damage >= staggerValues.threshold then
		-- Normal stagger threshold
		return true
	end

	return false
end

-- Apply stagger to entity
function StaggerSystem.tryStagger(targetId: string, damage: number, sourceId: string?, specId: string?): boolean
	if not shouldStagger(targetId, damage, specId) then
		return false
	end

	-- Compute dynamic stagger duration based on current stats
	local staggerValues = StaggerCalculator.computeAll(targetId, specId)

	-- Apply stagger status effect with computed duration
	local params = {
		duration = staggerValues.duration,
	}

	StatusEffectsService.apply(targetId, "stagger", sourceId, params)

	-- Update last stagger time
	lastStaggerTime[targetId] = os.clock()

	print(
		`[StaggerSystem] Staggered {targetId} for {staggerValues.duration}s (damage: {damage}, threshold: {staggerValues.threshold})`
	)
	return true
end

-- Initialize stagger system (no longer listens to HitEvent - called directly from CombatService)
function StaggerSystem.init()
	print("[StaggerSystem] Initialized")
end

return StaggerSystem
