local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SkillsConfig = require(script.Parent.SkillsConfig)
local Networking = require(ReplicatedStorage.Shared.Networking)
local CooldownService = require(script.Parent.CooldownService)
local ComboService = require(script.Parent.ComboService)
local ExecutionService = require(script.Parent.ExecutionService)
require(script.Parent.SkillsEvent)

local SkillsManager = {}

type Caster = Instance

local casterSkills: { [Caster]: { [string]: any } } = {} -- Table to hold skills per caster

-- Forward declare type for function without defining it
local useSkill: (caster: Caster, skillName: string, requestData: any?) -> ()

local SKILLS_CHANNEL_NAME = "Skills"
local dispatcher = Networking.server()
local dispatcherAny = dispatcher :: any
dispatcherAny:_ensureChannel(SKILLS_CHANNEL_NAME)

dispatcherAny:onRequest("SkillsRequest", function(requestData, _meta, context)
	local player = context.player
	if not player then
		return { success = false, error = "no_player" }
	end
	if not requestData or requestData.action ~= "use" then
		return { success = false, error = "invalid_action" }
	end

	local skillName = requestData.skillName
	if type(skillName) ~= "string" then
		return { success = false, error = "invalid_skill" }
	end

	useSkill(player, skillName, requestData)
	return { success = true }
end)

function SkillsManager.addSkill(caster: Caster, name: string, override: SkillsConfig.SkillConfigOverride?)
	local skill = SkillsConfig.addSkill(caster, name, override)
	casterSkills[caster] = casterSkills[caster] or {}
	casterSkills[caster][name] = skill
	return skill
end

-- Listen for execution completion to start cooldown + GCD
ExecutionService.onCompleted(function(caster: Caster, completedSkill: string, _reason: string)
	local skills = casterSkills[caster]
	if not skills then return end
	local skill = skills[completedSkill]
	if not skill then return end
	-- Start GCD & cooldown now (completion-based model)
	if skill.gcd and skill.gcd > 0 then
		CooldownService.startGCD(caster, skill.gcd)
	end
	if skill.cooldown and skill.cooldown > 0 then
		CooldownService.start(caster, completedSkill, skill.cooldown)
	end
end)

function SkillsManager.useSkill(caster: Caster, skillName: string, requestData: any?)
	local skills = casterSkills[caster]
	if not skills then
		warn(`No skills found for caster {caster}`)
		return
	end

	local skill = skills[skillName]
	if not skill then
		warn(`Skill '{skillName}' not found for caster {caster}`)
		return
	end

	local skillCfg = skill.config or SkillsConfig.skills[skillName]
	local comboCfg = skillCfg and skillCfg.combo

	-- Block if main skill cooldown active (cooldown gating between full uses)
	local onCD = CooldownService.isOnCooldown(caster, skillName)
	if onCD then return end

	-- Block based on execution lock:
	-- 1. If locked by a DIFFERENT skill -> always block.
	-- 2. If locked by the SAME skill:
	--    - Allow only if this skill is a combo (chaining next step)
	--    - Otherwise block to prevent spam (e.g., TripleStrike re-fire mid execution)
	local locked, lockedSkill = ExecutionService.isLocked(caster)
	if locked then
		if lockedSkill ~= skillName then
			return -- different skill executing
		end
		-- Same skill locked
		if not comboCfg then
			return -- non-combo skill cannot be re-used during its own execution
		end
	end

	if comboCfg then
		local step, token, advanced = ComboService.nextStep(caster, skillName, comboCfg.steps, comboCfg.window, comboCfg.stepDelays)
		if not advanced then return end
		local req = requestData or {}
		req.combo = {
			step = step,
			total = comboCfg.steps,
			token = token,
			window = comboCfg.window,
			finalCd = comboCfg.comboCooldown or skill.cooldown,
		}
		skill:use(req)
		return
	else
		-- Non-combo: just execute
		if requestData ~= nil then
			skill:use(requestData)
		else
			skill:use()
		end
	end
end

-- Assign to local alias after definition
useSkill = SkillsManager.useSkill

function SkillsManager.removeAll(caster: Caster)
	local skills = casterSkills[caster]
	if not skills then
		return
	end
	casterSkills[caster] = nil
	-- TODO: Consider calling cleanup hooks on skill instances if needed
end

function SkillsManager.getSkill(caster: Caster, skillName: string)
	local skills = casterSkills[caster]
	if not skills then
		return nil
	end
	return skills[skillName]
end

function SkillsManager.getSkillConfig(caster: Caster, skillName: string)
	local skill = SkillsManager.getSkill(caster, skillName)
	if skill and skill.config then
		return skill.config
	end
	return nil
end

return SkillsManager
