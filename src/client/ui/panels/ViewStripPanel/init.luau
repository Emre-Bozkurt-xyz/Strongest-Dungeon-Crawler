--!strict
-- The menu's views as one strip: SYSTEM, INVENTORY, EQUIPMENT, LOADOUT, each with its key. The views
-- were always one menu, but each was reachable only by its own key, so nothing said the others were
-- there. Clicking a tab switches to it.
--
-- A panel of its own on the stage rather than part of any view's panel: it belongs to the menu, not to
-- a view, so it stays up across a switch and MenuRigRuntime glides it over to whichever panel is
-- primary. It is drawn in the world like the panels it heads, not on the screen over them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

local useMenuState = require(script.Parent.Parent.hooks.useMenuState)
local ThemeContext = require(script.Parent.Parent.hooks.ThemeContext)
local MenuOrchestrator = require(script.Parent.Parent.menu.MenuOrchestrator)
local MenuTypes = require(script.Parent.Parent.menu.MenuTypes)
local PanelFrame = require(script.Parent.Parent.components.PanelFrame)
local UISound = require(script.Parent.Parent.UISound)

local e = React.createElement

-- The surface's logical size (PanelRegistry): four tabs across.
local TAB_WIDTH = 140
local HEIGHT = 44

local TABS: { { view: MenuTypes.MenuView, label: string, key: string } } = {
	{ view = "system", label = "SYSTEM", key = "J" },
	{ view = "inventory", label = "INVENTORY", key = "I" },
	{ view = "equipment", label = "EQUIPMENT", key = "K" },
	{ view = "loadout", label = "LOADOUT", key = "L" },
}

local function Tab(props: { label: string, keyLabel: string, active: boolean, order: number, onActivated: () -> () })
	local theme = ThemeContext.useTheme()
	local hovered, setHovered = React.useState(false)
	local lit = props.active or hovered
	return e("TextButton", {
		Size = UDim2.fromOffset(TAB_WIDTH, HEIGHT),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = props.order,
		[React.Event.MouseEnter] = function()
			setHovered(true)
			if not props.active then
				UISound.play("hover")
			end
		end,
		[React.Event.MouseLeave] = function()
			setHovered(false)
		end,
		[React.Event.Activated] = props.onActivated,
	}, {
		Row = e("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
		}, {
			Layout = e("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, 8),
			}),
			Label = e("TextLabel", {
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, HEIGHT),
				BackgroundTransparency = 1,
				Text = props.label,
				-- The bold body face: the display face blurs at a size that fits four tabs across.
				FontFace = theme.face.bodyBold,
				TextSize = 20,
				TextColor3 = if lit then theme.color.textPrimary else theme.color.textMuted,
				LayoutOrder = 1,
			}),
			Key = e("TextLabel", {
				Size = UDim2.fromOffset(24, 24),
				BackgroundTransparency = 1,
				Text = props.keyLabel,
				FontFace = theme.face.mono,
				TextSize = 17,
				-- Muted, not disabled, when idle: on a world surface the disabled tone drops out entirely.
				TextColor3 = if props.active then theme.color.textPrimary else theme.color.textMuted,
				LayoutOrder = 2,
			}, {
				Stroke = e("UIStroke", {
					Color = theme.color.stroke,
					Thickness = 1,
					Transparency = if props.active then 0.55 else 0.8,
					ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				}),
			}),
		}),
		Underline = e("Frame", {
			Size = UDim2.new(1, -28, 0, 2),
			Position = UDim2.new(0.5, 0, 1, -5),
			AnchorPoint = Vector2.new(0.5, 1),
			BackgroundColor3 = theme.color.accent,
			BackgroundTransparency = if props.active then 0 elseif hovered then 0.7 else 1,
			BorderSizePixel = 0,
		}),
	})
end

local function ViewStripPanel()
	local state = useMenuState()
	if not state then
		return nil
	end
	-- Rendered while closing too, still marking the view it closes on.
	local view = state.modal.view

	local tabs: { [string]: any } = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}
	for order, tab in ipairs(TABS) do
		tabs[tab.label] = e(Tab, {
			label = tab.label,
			keyLabel = tab.key,
			active = view == tab.view,
			order = order,
			onActivated = function()
				if state.modal.open and view ~= tab.view then
					UISound.play("confirm")
					MenuOrchestrator.setView(tab.view)
				end
			end,
		})
	end

	return e(PanelFrame, {
		layout = "free",
		padding = 0,
		brackets = "small",
	}, {
		Tabs = e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, tabs),
	})
end

return ViewStripPanel
