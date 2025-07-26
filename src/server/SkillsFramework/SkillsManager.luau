local SkillsConfig = require(script.Parent.SkillsConfig)
local NetworkManager = require(script.Parent.Parent.NetworkManager)

local SkillsManager = {}

local playerSkills = {} -- Table to hold player skills

local handler = {
	serialize = function(_data: any): string
		return "test"
	end,

	deserialize = function(_data: any): any
		-- Deserialize data from client
		return true
	end,

	applyDelta = function(_: any, delta: any): boolean
		-- Apply the delta
		print("DELTA RECEIVED:", delta)
		if not delta then
			warn("Invalid delta received for skills")
			return false
		end

		if delta.target == "use_skill" then
			local playerId = delta.data.playerId

			local player = game.Players:GetPlayerByUserId(playerId)
			if not player then
				warn(`Player with ID {playerId} not found`)
				return false
			end

			SkillsManager.useSkill(player, delta.data.skillName)
			return true
		end

		return false
	end,
}

function SkillsManager.addSkill(player: Player, name: string)
	local skill = SkillsConfig.addSkill(player, name)
	-- Additional logic for managing the skill can be added here
	playerSkills[player] = playerSkills[player] or {}
	playerSkills[player][name] = skill
	return skill
end

function SkillsManager.useSkill(player: Player, skillName: string)
	local skills = playerSkills[player]
	if not skills then
		warn(`No skills found for player {player}`)
		return
	end

	local skill = skills[skillName]
	if skill then
		skill:use()
	else
		warn(`Skill '{skillName}' not found for player {player}`)
	end
end

NetworkManager.registerSystem("skills", handler)

return SkillsManager
