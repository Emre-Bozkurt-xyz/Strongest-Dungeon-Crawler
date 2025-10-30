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

function SkillsManager.addSkill(caster: Caster, name: string, override: SkillsConfig.SkillConfigOverride?)
	local skill = SkillsConfig.addSkill(caster, name, override)
	casterSkills[caster] = casterSkills[caster] or {}
	casterSkills[caster][name] = skill
	return skill
end

-- Listen for execution completion to start cooldown + GCD
ExecutionService.onCompleted(function(caster: Caster, completedSkill: string, _reason: string)
	local skills = casterSkills[caster]
	if not skills then
		return
	end
	local skill = skills[completedSkill]
	if not skill then
		return
	end
	if skill.config and skill.config.combo then
		ComboService.clear(caster, completedSkill)
	end
	-- Start GCD & cooldown now (completion-based model)
	if skill.gcd and skill.gcd > 0 then
		CooldownService.startGCD(caster, skill.gcd)
	end
	if skill.cooldown and skill.cooldown > 0 then
		CooldownService.start(caster, completedSkill, skill.cooldown)
	end
end)

function SkillsManager.canUse(caster: Caster, skillName: string): (boolean, string?)
	local skills = casterSkills[caster]
	if not skills then
		return false, "no_skills"
	end

	local skill = skills[skillName]
	if not skill then
		return false, "no_skill"
	end

	local skillCfg = skill.config or SkillsConfig.skills[skillName]
	local comboCfg = skillCfg and skillCfg.combo

	-- Block if main skill cooldown active (cooldown gating between full uses)
	local onCD = CooldownService.isOnCooldown(caster, skillName)
	if onCD then
		return false, "on_cooldown"
	end

	-- Block based on execution lock:
	-- 1. If locked by a DIFFERENT skill -> always block.
	-- 2. If locked by the SAME skill:
	--    - Allow only if this skill is a combo (chaining next step)
	--    - Otherwise block to prevent spam (e.g., TripleStrike re-fire mid execution)
	local locked, lockedSkill = ExecutionService.isLocked(caster)
	if locked then
		if lockedSkill ~= skillName then
			return false, "locked_by_different_skill"
		end
		-- Same skill locked
		if not comboCfg then
			return false, "locked_by_same_skill"
		end
	end

	return true
end

function SkillsManager.useSkill(caster: Caster, skillName: string, requestData: any?): any
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
	if onCD then
		return
	end

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
		local advance = ComboService.requestStep(caster, skillName, comboCfg.steps)
		if not advance then
			return
		end
		local req = requestData or {}
		req.combo = {
			step = advance.step,
			total = comboCfg.steps,
			token = advance.token,
			window = comboCfg.window,
			startedAt = advance.startedAt,
			isNewChain = advance.isNewChain,
			finalCd = comboCfg.comboCooldown or skill.cooldown,
		}
		skill:use(req)
		return {
			step = advance.step,
			total = comboCfg.steps,
			window = comboCfg.window,
		}
	else
		-- Non-combo: just execute
		if requestData ~= nil then
			skill:use(requestData)
		else
			skill:use()
		end
	end

	return
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

dispatcher:onRequest("SkillRequestUse", function(requestData, _meta, context)
	local player = context.player
	if not player then
		return { success = false, error = "no_player" }
	end
	local skillName = requestData.skillName
	local result, reason = SkillsManager.canUse(player, skillName)
	if not result then
		return { success = false, error = reason }
	end
	local data = SkillsManager.useSkill(player, skillName, requestData)
	return { success = true, data = data }
end)

return SkillsManager
