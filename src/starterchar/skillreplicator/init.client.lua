-- local Player = game:GetService("Players")
-- local Character = script.Parent

-- local UserInputService = game:GetService("UserInputService")
-- local RS = game:GetService("ReplicatedStorage")

-- local Cooldown = require(RS.Shared.SkillFramework.Cooldown)
-- local Skillsets = require(RS.Shared.SkillFramework.Skillsets)
-- local VFX = require(script:WaitForChild("FX")) :: any

-- local AvailableSets = {
--     "Combat",
--     "Movement"
-- }

-- local InputBegan = coroutine.create(function()
--     UserInputService.InputBegan:Connect(function(input, gameProcessed)
--         if gameProcessed then return end

--         local Skill, Set, Info, Input = nil

--         if input.UserInputType == Enum.UserInputType.MouseButton1 then
--             Input = "M1"
--             Info = {
--                 Data = "Test"
--             }
--         elseif input.UserInputType == Enum.UserInputType.Keyboard then
--             Input = input.KeyCode.Name
--         end

--     end)
-- end)
