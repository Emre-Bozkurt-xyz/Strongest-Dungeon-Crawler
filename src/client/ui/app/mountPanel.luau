--!strict
-- Creates a React root on a surface and wraps the element in the providers every component expects.
--
-- Per-surface roots rather than one root portalling into each surface (R9 in
-- docs/tasks/ui-migration-plan.md): world surfaces are created and destroyed by imperative rig code,
-- and a portal into an instance React does not own forces a two-phase teardown. A root per surface
-- makes teardown sequential -- unmount, then destroy.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)
local Themes = require(ReplicatedStorage.Shared.ui.themes)
local ThemeContext = require(script.Parent.Parent.hooks.ThemeContext)

export type MountedPanel = {
	-- Re-render with a new element, keeping the same root and provider. Passing nil renders nothing,
	-- which is how a hidden panel drops its subtree without tearing down its surface (R16).
	render: (element: any) -> (),
	unmount: () -> (),
}

-- `container` is the instance React renders into: a SurfaceGui or CanvasGroup for world panels, a
-- ScreenGui or Frame for screen-space UI.
local function mountPanel(container: Instance, element: any, theme: Themes.Theme?): MountedPanel
	local root = ReactRoblox.createRoot(container)
	local resolvedTheme = theme or Themes.getDefault()
	local unmounted = false

	local function render(next: any)
		if unmounted then
			return
		end
		root:render(React.createElement(ThemeContext.Provider, {
			value = resolvedTheme,
		}, next))
	end

	render(element)

	return {
		render = render,
		unmount = function()
			if unmounted then
				return
			end
			unmounted = true
			root:unmount()
		end,
	}
end

return mountPanel
