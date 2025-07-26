local UserInputService = game:GetService("UserInputService")
local SkillsClient = require(script.Parent.SkillsClient)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		local skillName = "Punch" -- Example skill name
		SkillsClient.useSkill(skillName)
	end
end)
