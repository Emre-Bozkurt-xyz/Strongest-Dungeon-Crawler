local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SkillsConfig = require(script.Parent.SkillsConfig)
local NetRay = require(ReplicatedStorage.Packages.NetRay)
local CooldownService = require(script.Parent.CooldownService)
local ComboService = require(script.Parent.ComboService)
local ExecutionService = require(script.Parent.ExecutionService)

-- Ensure SkillsEvent exists for client FX hooks
NetRay:RegisterEvent("SkillsEvent")

local SkillsManager = {}

local playerSkills = {} -- Table to hold player skills

-- Forward declare type for function without defining it
local useSkill: (player: Player, skillName: string, requestData: any?) -> ()

-- NetRay request endpoint
local skillsRequest = NetRay:RegisterRequestEvent("SkillsRequest")

skillsRequest:OnRequest(function(player: Player, requestData)
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

function SkillsManager.addSkill(player: Player, name: string)
	local skill = SkillsConfig.addSkill(player, name)
	playerSkills[player] = playerSkills[player] or {}
	playerSkills[player][name] = skill
	return skill
end

-- Listen for execution completion to start cooldown + GCD
ExecutionService.onCompleted(function(player: Player, completedSkill: string, _reason: string)
	local skills = playerSkills[player]
	if not skills then return end
	local skill = skills[completedSkill]
	if not skill then return end
	-- Start GCD & cooldown now (completion-based model)
	if skill.gcd and skill.gcd > 0 then
		CooldownService.startGCD(player, skill.gcd)
	end
	if skill.cooldown and skill.cooldown > 0 then
		CooldownService.start(player, completedSkill, skill.cooldown)
	end
end)

function SkillsManager.useSkill(player: Player, skillName: string, requestData: any?)
	local skills = playerSkills[player]
	if not skills then
		warn(`No skills found for player {player}`)
		return
	end

	local skill = skills[skillName]
	if not skill then
		warn(`Skill '{skillName}' not found for player {player}`)
		return
	end

	local skillCfg = SkillsConfig.skills[skillName]
	local comboCfg = skillCfg and skillCfg.combo

	-- Block if main skill cooldown active (cooldown gating between full uses)
	local onCD = CooldownService.isOnCooldown(player, skillName)
	if onCD then return end

	-- Block based on execution lock:
	-- 1. If locked by a DIFFERENT skill -> always block.
	-- 2. If locked by the SAME skill:
	--    - Allow only if this skill is a combo (chaining next step)
	--    - Otherwise block to prevent spam (e.g., TripleStrike re-fire mid execution)
	local locked, lockedSkill = ExecutionService.isLocked(player)
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
		local step, token, advanced = ComboService.nextStep(player, skillName, comboCfg.steps, comboCfg.window, comboCfg.stepDelays)
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

return SkillsManager
