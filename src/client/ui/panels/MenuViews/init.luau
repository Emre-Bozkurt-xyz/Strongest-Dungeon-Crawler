--!strict
-- The menu's views as one strip at the top of the screen while the menu is open: SYSTEM, INVENTORY,
-- EQUIPMENT, LOADOUT, each with its key. The views were always one menu, but each was reachable only
-- by its own key, so nothing on screen said the others were there. Clicking a tab switches to it.
--
-- Screen space rather than on the staged panels: the strip belongs to the menu, not to any one
-- panel, and it stays put while the camera moves between views.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

local useMenuState = require(script.Parent.Parent.hooks.useMenuState)
local ThemeContext = require(script.Parent.Parent.hooks.ThemeContext)
local MenuOrchestrator = require(script.Parent.Parent.menu.MenuOrchestrator)
local MenuTypes = require(script.Parent.Parent.menu.MenuTypes)
local Brackets = require(script.Parent.Parent.components.Brackets)
local UISound = require(script.Parent.Parent.UISound)

local e = React.createElement

-- In the empty middle of Roblox's top bar, clear of the staged panels below it.
local TOP = 10
local TAB_WIDTH = 176
local HEIGHT = 40

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
				Padding = UDim.new(0, 10),
			}),
			Label = e("TextLabel", {
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, HEIGHT),
				BackgroundTransparency = 1,
				Text = props.label,
				FontFace = theme.face.display,
				TextSize = 13,
				TextColor3 = if lit then theme.color.textPrimary else theme.color.textMuted,
				LayoutOrder = 1,
			}),
			Key = e("TextLabel", {
				Size = UDim2.fromOffset(18, 18),
				BackgroundTransparency = 1,
				Text = props.keyLabel,
				FontFace = theme.face.mono,
				TextSize = 11,
				TextColor3 = if props.active then theme.color.textMuted else theme.color.textDisabled,
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
			Size = UDim2.new(1, -24, 0, 2),
			Position = UDim2.fromScale(0.5, 1),
			AnchorPoint = Vector2.new(0.5, 1),
			BackgroundColor3 = theme.color.accent,
			BackgroundTransparency = if props.active then 0 elseif hovered then 0.7 else 1,
			BorderSizePixel = 0,
		}),
	})
end

local function MenuViews()
	local state = useMenuState()
	if not (state and state.modal.open) then
		return nil
	end

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
			active = state.modal.view == tab.view,
			order = order,
			onActivated = function()
				if state.modal.view ~= tab.view then
					UISound.play("confirm")
					MenuOrchestrator.setView(tab.view)
				end
			end,
		})
	end

	return e("Frame", {
		Size = UDim2.fromOffset(TAB_WIDTH * #TABS, HEIGHT),
		Position = UDim2.new(0.5, 0, 0, TOP),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
	}, {
		Fade = e("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.6),
				NumberSequenceKeypoint.new(0.15, 0),
				NumberSequenceKeypoint.new(0.85, 0),
				NumberSequenceKeypoint.new(1, 0.6),
			}),
		}),
		Corners = e(Brackets, { size = "small", edgeTransparency = 1 }),
		Tabs = e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, tabs),
	})
end

return MenuViews
