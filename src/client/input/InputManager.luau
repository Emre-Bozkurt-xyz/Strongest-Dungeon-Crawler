--!strict
-- InputManager: Lightweight action binding dispatcher built atop UserInputService.
-- Mirrors Roblox's forthcoming InputContext/InputAction structure so we can later
-- swap internals with minimal external changes.

local UserInputService = game:GetService("UserInputService")

local ActionConfig = require(script.Parent.ActionConfig)

export type ActionCallback = (actionName: string, bindingMeta: { [string]: any }?) -> ()

type InternalAction = ActionConfig.ActionSpec & { callbackList: { ActionCallback } }

local InputManager = {}
InputManager.__index = InputManager

local _instance: any = nil

-- Map: actionName -> InternalAction
local actions: { [string]: InternalAction } = {}

-- Context filter (optional runtime enable/disable)
local contextEnabled: { [string]: boolean } = {}

local function normalize()
    for ctxName, ctx in pairs(ActionConfig.contexts) do
        contextEnabled[ctxName] = ctx.enabled
        for actionName, spec in pairs(ctx.actions) do
            actions[actionName] = {
                name = spec.name,
                bindings = spec.bindings,
                context = ctxName,
                consume = spec.consume,
                callbackList = {},
            }
        end
    end
end

local function bindingMatches(b, input: InputObject, began: boolean)
    if b.key and input.KeyCode == b.key then
        if b.type == "press" and began then return true end
        if b.type == "release" and not began then return true end
    end
    if b.mouse and input.UserInputType == b.mouse then
        if b.type == "press" and began then return true end
        if b.type == "release" and not began then return true end
    end
    return false
end

function InputManager.new()
    if _instance then return _instance end
    local self = setmetatable({}, InputManager)
    normalize()

    UserInputService.InputBegan:Connect(function(input, gpe)
        if gpe then return end
        for _, act in pairs(actions) do
            if contextEnabled[act.context] then
                for _, b in ipairs(act.bindings) do
                    if bindingMatches(b, input, true) then
                        for _, cb in ipairs(act.callbackList) do
                            task.spawn(cb, act.name, b.meta)
                        end
                        break
                    end
                end
            end
        end
    end)

    UserInputService.InputEnded:Connect(function(input, gpe)
        if gpe then return end
        for _, act in pairs(actions) do
            if contextEnabled[act.context] then
                for _, b in ipairs(act.bindings) do
                    if bindingMatches(b, input, false) then
                        for _, cb in ipairs(act.callbackList) do
                            task.spawn(cb, act.name, b.meta)
                        end
                        break
                    end
                end
            end
        end
    end)

    _instance = self
    return self
end

function InputManager.get()
    return _instance or InputManager.new()
end

function InputManager.on(actionName: string, callback: ActionCallback)
    local act = actions[actionName]
    if not act then
        error("InputManager: Unknown action " .. actionName)
    end
    table.insert(act.callbackList, callback)
end

function InputManager.setContextEnabled(ctx: string, enabled: boolean)
    if contextEnabled[ctx] == nil then
        error("InputManager: Unknown context " .. ctx)
    end
    contextEnabled[ctx] = enabled
end

-- Future: Rebinding persistence (stub)
function InputManager.rebind(actionName: string, newBinding: ActionConfig.Binding)
    local act = actions[actionName]
    if not act then
        error("InputManager: Unknown action " .. actionName)
    end
    -- Replace first binding for now; could push or multi-map later
    act.bindings[1] = newBinding
end

return InputManager
