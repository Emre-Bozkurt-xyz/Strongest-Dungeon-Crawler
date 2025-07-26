local ClientNetworkManager = require(script.Parent.Parent.ClientNetworkManager)

local Player = game:GetService("Players").LocalPlayer

local SkillsClient = {}

function SkillsClient.useSkill(skillName: string)
	ClientNetworkManager.sendDelta({
		system = "skills",
		target = "use_skill",
		timestamp = tick(),
		type = "use",
		data = {
			playerId = Player.UserId,
			skillName = skillName,
		},
	})
end

return SkillsClient
