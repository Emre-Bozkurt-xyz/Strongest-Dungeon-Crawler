--!strict
-- InputManager: Lightweight action binding dispatcher built atop UserInputService.
-- Mirrors Roblox's forthcoming InputContext/InputAction structure so we can later
-- swap internals with minimal external changes.

local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ActionConfig = require(script.Parent.ActionConfig)
local DebugConfig = require(ReplicatedStorage.Shared.Debug.DebugConfig)

-- Temporary diagnostics for the "keybinds do nothing, no logs" investigation.
-- Gated on the existing `inputFlow` flag (enabled in client dev/InitDev).
local function logFlow(...: any)
	if DebugConfig.isEnabled("inputFlow") then
		print("[InputFlow]", ...)
	end
end

export type ActionCallback = (actionName: string, bindingMeta: { [string]: any }?) -> ()

type InternalAction = ActionConfig.ActionSpec & { callbackList: { ActionCallback } }

local InputManager = {}
InputManager.__index = InputManager

local _instance: any = nil
local CAS_PRIORITY_BASE = 3000

-- Map: actionName -> InternalAction
local actions: { [string]: InternalAction } = {}

-- Context filter (optional runtime enable/disable)
local contextEnabled: { [string]: boolean } = {}
local actionPriorities: { [string]: number } = {}

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
			actionPriorities[actionName] = ctx.priority
        end
    end
end

local function getShiftDown(): boolean
	return UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
end

local function getCtrlDown(): boolean
	return UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
end

local function getAltDown(): boolean
	return UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt) or UserInputService:IsKeyDown(Enum.KeyCode.RightAlt)
end

local function getModifierStateForInput(input: InputObject): (boolean, boolean, boolean)
	local shift = getShiftDown()
	local ctrl = getCtrlDown()
	local alt = getAltDown()
	local keyCode = input.KeyCode

	if keyCode == Enum.KeyCode.LeftShift or keyCode == Enum.KeyCode.RightShift then
		shift = false
	end
	if keyCode == Enum.KeyCode.LeftControl or keyCode == Enum.KeyCode.RightControl then
		ctrl = false
	end
	if keyCode == Enum.KeyCode.LeftAlt or keyCode == Enum.KeyCode.RightAlt then
		alt = false
	end

	return shift, ctrl, alt
end

local function modifiersMatch(modifiers: { shift: boolean?, ctrl: boolean?, alt: boolean? }?, input: InputObject): boolean
	local shiftDown, ctrlDown, altDown = getModifierStateForInput(input)
	if modifiers == nil then
		return not (shiftDown or ctrlDown or altDown)
	end
	if modifiers.shift and not shiftDown then
		return false
	end
	if modifiers.ctrl and not ctrlDown then
		return false
	end
	if modifiers.alt and not altDown then
		return false
	end
	return true
end

local function bindingMatches(b, input: InputObject, began: boolean)
	if not modifiersMatch(b.modifiers, input) then
		return false
	end
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

local function shouldSuppressInput(): boolean
	return UserInputService:GetFocusedTextBox() ~= nil
end

local function buildMeta(b, input: InputObject, gameProcessedEvent: boolean): { [string]: any }
	local meta = b.meta and table.clone(b.meta) or {}
	meta.type = b.type
	meta.gameProcessedEvent = gameProcessedEvent
	meta.keyCode = input.KeyCode
	meta.userInputType = input.UserInputType
	return meta
end

local function dispatchActionInput(
	act: InternalAction,
	input: InputObject,
	began: boolean,
	gameProcessedEvent: boolean
): boolean
	local phase = if began then "press" else "release"

	if shouldSuppressInput() then
		logFlow(`{act.name}: SUPPRESSED ({phase}) - a TextBox has focus`)
		return false
	end

	if not contextEnabled[act.context] then
		logFlow(`{act.name}: BLOCKED ({phase}) - context '{act.context}' is disabled`)
		return false
	end

	local matched = false
	for _, b in ipairs(act.bindings) do
		if bindingMatches(b, input, began) then
			matched = true
			local meta = buildMeta(b, input, gameProcessedEvent)
			logFlow(`{act.name}: MATCHED ({phase}) -> firing {#act.callbackList} callback(s)`)
			for _, cb in ipairs(act.callbackList) do
				task.spawn(cb, act.name, meta)
			end
			break
		end
	end

	if not matched then
		local shiftDown, ctrlDown, altDown = getModifierStateForInput(input)
		logFlow(
			`{act.name}: NO BINDING MATCH ({phase}) key={input.KeyCode.Name} shift={shiftDown} ctrl={ctrlDown} alt={altDown}`
		)
	end

	return matched
end

local function getBindingInputs(action: InternalAction): { any }
	local inputs = {}
	local seen = {}

	for _, binding in ipairs(action.bindings) do
		local input = binding.key or binding.mouse or binding.gamepadButton
		if input and not seen[input] then
			seen[input] = true
			table.insert(inputs, input)
		end
	end

	return inputs
end

local function bindContextActions()
	for actionName, action in pairs(actions) do
		local inputs = getBindingInputs(action)
		if #inputs == 0 then
			logFlow(`bind: '{actionName}' has NO inputs - never bound`)
		end
		if #inputs > 0 then
			local names: { string } = {}
			for _, entry in ipairs(inputs) do
				table.insert(names, tostring((entry :: any).Name or entry))
			end
			logFlow(
				`bind: '{actionName}' ctx='{action.context}' enabled={contextEnabled[action.context]} keys=[{table.concat(names, ", ")}]`
			)
			ContextActionService:BindActionAtPriority(
				"SDC_" .. actionName,
				function(_boundName: string, inputState: Enum.UserInputState, input: InputObject)
					if inputState == Enum.UserInputState.Begin then
						local matched = dispatchActionInput(action, input, true, false)
						return if matched and action.consume then Enum.ContextActionResult.Sink else Enum.ContextActionResult.Pass
					end
					if inputState == Enum.UserInputState.End then
						local matched = dispatchActionInput(action, input, false, false)
						return if matched and action.consume then Enum.ContextActionResult.Sink else Enum.ContextActionResult.Pass
					end
					return Enum.ContextActionResult.Pass
				end,
				false,
				CAS_PRIORITY_BASE + (actionPriorities[actionName] or 100),
				table.unpack(inputs)
			)
		end
	end
end

function InputManager.new()
    if _instance then return _instance end
    local self = setmetatable({}, InputManager)
    normalize()
	bindContextActions()

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
