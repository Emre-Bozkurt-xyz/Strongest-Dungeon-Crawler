--!strict
-- Inputs: wires high-level action callbacks into the input manager.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SkillSlots = require(script.Parent.SkillsFramework.SkillSlots)
local InputManager = require(script.Parent.input.InputManager)
local InteractionStateController = require(script.Parent.input.InteractionStateController)
local MenuOrchestrator = require(script.Parent.ui.menu.MenuOrchestrator)
local DebugConfig = require(ReplicatedStorage.Shared.Debug.DebugConfig)

local Inputs = {}
local initialized = false

-- Temporary diagnostics: both skill guards below return silently, which makes a blocked
-- keypress indistinguishable from a dead binding. Gated on the existing `inputFlow` flag.
local function logFlow(...: any)
	if DebugConfig.isEnabled("inputFlow") then
		print("[InputFlow]", ...)
	end
end

local function toggleMenuView(view: string)
	MenuOrchestrator.toggleView(view :: any)
end

function Inputs.init()
	if initialized then
		return
	end
	initialized = true

	InputManager.get()

	InputManager.on("MenuViewSystem", function()
		toggleMenuView("system")
	end)

	InputManager.on("MenuViewInventory", function()
		toggleMenuView("inventory")
	end)

	InputManager.on("MenuViewEquipment", function()
		toggleMenuView("equipment")
	end)

	InputManager.on("PrecisionFocus", function(_action, meta)
		if meta and meta.type == "release" then
			InteractionStateController.setPrecisionFocusHeld(false)
		else
			InteractionStateController.setPrecisionFocusHeld(true)
		end
	end)

	for i = 1, 5 do
		local actionName = "Skill" .. tostring(i)
		InputManager.on(actionName, function(_action, meta)
			local phase = if meta and meta.type == "release" then "release" else "press"
			logFlow(`Skill{i}: handler entered ({phase})`)
			if MenuOrchestrator.isGameplayBlocked() then
				logFlow(`Skill{i}: BLOCKED - MenuOrchestrator.isGameplayBlocked() == true`)
				return
			end
			if InteractionStateController.allowsWorldPanelInteraction() then
				logFlow(`Skill{i}: BLOCKED - allowsWorldPanelInteraction() == true (precision focus / world panel)`)
				return
			end
			if meta and meta.type == "release" then
				SkillSlots.release(i)
			else
				SkillSlots.activate(i)
			end
		end)
	end

	InputManager.on("CycleSkillProfile", function()
		if MenuOrchestrator.isGameplayBlocked() then
			return
		end
		if InteractionStateController.allowsWorldPanelInteraction() then
			return
		end
		SkillSlots.cycleProfile(1)
	end)

	InputManager.on("CycleSkillProfilePrev", function()
		if MenuOrchestrator.isGameplayBlocked() then
			return
		end
		if InteractionStateController.allowsWorldPanelInteraction() then
			return
		end
		SkillSlots.cycleProfile(-1)
	end)
end

return Inputs
