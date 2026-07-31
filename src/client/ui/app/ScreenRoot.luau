--!strict
-- The persistent screen-space React root: HUD, damage numbers, and every cross-surface concern
-- (drag previews, tooltips, modals) that must float above world panels.
--
-- Created in code rather than pre-placed under StarterGui. The only reason UI lived there was live
-- editing in Studio, which no longer applies (R9 in docs/tasks/ui-migration-plan.md).

local Players = game:GetService("Players")

local mountPanel = require(script.Parent.mountPanel)

local ScreenRoot = {}

local SCREEN_GUI_NAME = "GameUI"

local mounted: mountPanel.MountedPanel? = nil
local screenGui: ScreenGui? = nil

local function createScreenGui(): ScreenGui
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = SCREEN_GUI_NAME
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui

	return gui
end

-- `element` is the root component for screen-space UI. Mounting is idempotent.
function ScreenRoot.start(element: any)
	if mounted then
		return
	end
	screenGui = createScreenGui()
	mounted = mountPanel(screenGui :: ScreenGui, element)
end

function ScreenRoot.stop()
	if mounted then
		mounted.unmount()
		mounted = nil
	end
	if screenGui then
		screenGui:Destroy()
		screenGui = nil
	end
end

function ScreenRoot.getScreenGui(): ScreenGui?
	return screenGui
end

return ScreenRoot
