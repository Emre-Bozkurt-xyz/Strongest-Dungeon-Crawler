local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SkillsConfig = require(script.Parent.SkillsConfig)
local NetRay = require(ReplicatedStorage.Packages.NetRay)
local CooldownService = require(script.Parent.CooldownService)
local ComboService = require(script.Parent.ComboService)

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

	-- Combo-enabled skill handling
	if comboCfg then
		-- Block if cooldown active (only enforced between whole combos)
		local onCD = CooldownService.isOnCooldown(player, skillName)
		if onCD then
			return
		end

		local step, token, advanced =
			ComboService.nextStep(player, skillName, comboCfg.steps, comboCfg.window, comboCfg.stepDelays)
		if not advanced then
			-- still in per-step lockout; ignore spam
			return
		end

		local req = requestData or {}
		req.combo = {
			step = step,
			total = comboCfg.steps,
			token = token,
			window = comboCfg.window,
			finalCd = comboCfg.comboCooldown or skill.cooldown,
		}
		skill:use(req)

		-- If final step executed, start cooldown now
		if step == comboCfg.steps then
			local finalCd = comboCfg.comboCooldown or skill.cooldown
			if finalCd and finalCd > 0 then
				CooldownService.start(player, skillName, finalCd)
			end
		end
		return
	end

	-- Non-combo skill normal path
	local onCD = CooldownService.isOnCooldown(player, skillName)
	if onCD then
		return
	end
	CooldownService.startGCD(player, skill.gcd)
	CooldownService.start(player, skillName, skill.cooldown)

	if requestData ~= nil then
		skill:use(requestData)
	else
		skill:use()
	end
end

-- Assign to local alias after definition
useSkill = SkillsManager.useSkill

return SkillsManager
