local UserInputService = game:GetService("UserInputService")
local SkillsClient = require(script.Parent.SkillsClient)
local SystemPanelHandler = require(script.Parent.Parent.SystemPanelHandler)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		local skillName = "Punch" -- Example skill name
		SkillsClient.useSkill(skillName)
	end

	if input.KeyCode == Enum.KeyCode.E then
		SystemPanelHandler.toggle()
	end
end)
