-- Inputs.client now just wires high-level action callbacks.
local SkillSlots = require(script.Parent.SkillsFramework.SkillSlots)
local SystemPanelHandler = require(script.Parent.ui.controllers.SystemPanelHandler)
local InputManager = require(script.Parent.input.InputManager)

InputManager.get() -- ensure initialization

-- Toggle system panel
InputManager.on("ToggleSystemPanel", function(_action, _meta)
    SystemPanelHandler.toggle()
end)

-- Skill slot activations (Skill1..Skill5 for now)
for i = 1, 5 do
    local actionName = "Skill" .. tostring(i)
    InputManager.on(actionName, function()
        SkillSlots.activate(i)
    end)
end

-- Profile cycling (LeftAlt)
InputManager.on("CycleSkillProfile", function()
    SkillSlots.cycleProfile(1)
end)

-- Profile cycling backward (RightAlt)
InputManager.on("CycleSkillProfilePrev", function()
    SkillSlots.cycleProfile(-1)
end)
