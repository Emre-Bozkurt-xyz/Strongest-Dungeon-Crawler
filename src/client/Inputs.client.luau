-- Inputs.client now just wires high-level action callbacks.
local SkillSlots = require(script.Parent.SkillsFramework.SkillSlots)
local SystemPanelHandler = require(script.Parent.ui.controllers.SystemPanelHandler)
local InputManager = require(script.Parent.input.InputManager)

InputManager.get() -- ensure initialization

local function toggleMenuView(view: string)
    if SystemPanelHandler.toggleMenuView then
        SystemPanelHandler.toggleMenuView(view)
    end
end

InputManager.on("MenuViewSystem", function()
    toggleMenuView("system")
end)

InputManager.on("MenuViewInventory", function()
    toggleMenuView("inventory")
end)

InputManager.on("MenuViewEquipment", function()
    toggleMenuView("equipment")
end)

-- Skill slot activations (Skill1..Skill5 for now)
for i = 1, 5 do
    local actionName = "Skill" .. tostring(i)
    InputManager.on(actionName, function(_action, meta)
        if meta and meta.type == "release" then
            SkillSlots.release(i)
        else
            SkillSlots.activate(i)
        end
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
