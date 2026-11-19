--!strict
-- The in-game developer console (dev sessions only; ScreenRegistry mounts it when
-- DevAccess.isEnabled()). The backquote key toggles it.
--
-- Docked to the right edge at a fixed width and the full height, so the game stays in view while
-- spawning, swapping characters or flipping flags; the HUD stays up beside it. While open it takes
-- the cursor and keeps gameplay input (skills, targeting) from firing, the way the menu does, through
-- a named input capture that is given back on close.
--
-- A status header (scenario, stage, character -- real save or preset), tabs, and a command line on
-- every tab. Every action is a command run through DevCommandsClient (ConsoleStore); the Commands tab
-- builds a form for every registered command from its descriptor, so the console never lags behind
-- the registry.
--
-- Rendered only from the first time it is opened, then kept mounted and hidden, so typed text, open
-- forms and the tab survive closing it; ConsoleStore holds the rest across respawns.

local GuiService = game:GetService("GuiService")
local LogService = game:GetService("LogService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local React = require(ReplicatedStorage.Packages.React)
local ui = script.Parent.Parent
local ThemeContext = require(ui.hooks.ThemeContext)
local Brackets = require(ui.components.Brackets)
local UISound = require(ui.UISound)
local InteractionStateController = require(ui.Parent.input.InteractionStateController)

local ConsoleStore = require(script.ConsoleStore)
local useConsole = require(script.useConsole)
local Controls = require(script.Controls)
local StatusHeader = require(script.StatusHeader)
local CommandBar = require(script.CommandBar)

local Tabs = script.Tabs
local TAB_COMPONENTS: { [string]: any } = {
	scenarios = require(Tabs.ScenariosTab),
	character = require(Tabs.CharacterTab),
	world = require(Tabs.WorldTab),
	debug = require(Tabs.DebugTab),
	commands = require(Tabs.CommandsTab),
	log = require(Tabs.LogTab),
	inspect = require(Tabs.InspectTab),
}
local TAB_LABELS: { [string]: string } = {
	scenarios = "Scenarios",
	character = "Character",
	world = "World",
	debug = "Debug",
	commands = "Commands",
	log = "Log",
	inspect = "Inspect",
}

local e = React.createElement

-- Backquote: Roblox core binds nothing to it, the game binds nothing to it, and it is where a
-- console key usually is. F-keys are not used because core claims several of them.
local TOGGLE_KEY = Enum.KeyCode.Backquote
local TOGGLE_LABEL = "`"
local CAPTURE_NAME = "DevConsole"

local DOCK_WIDTH_SCALE = 0.34
local DOCK_MIN_WIDTH = 460
local DOCK_MAX_WIDTH = 600
local EDGE = 8
-- Room kept for the tab body's scroll bar.
local SCROLL_GUTTER = 16

local function TabStrip(props: { active: string, layoutOrder: number })
	local theme = ThemeContext.useTheme()
	local children: { [string]: any } = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalFlex = Enum.UIFlexAlignment.SpaceBetween,
			Wraps = true,
		}),
	}
	for index, id in ipairs(ConsoleStore.TABS) do
		local active = id == props.active
		children[id] = e("TextButton", {
			Text = string.upper(TAB_LABELS[id]),
			Size = UDim2.fromOffset(0, 34),
			AutomaticSize = Enum.AutomaticSize.X,
			LayoutOrder = index,
			BackgroundTransparency = 1,
			FontFace = theme.face.bodyBold,
			TextSize = Controls.SMALL,
			TextColor3 = if active then theme.color.textPrimary else theme.color.textMuted,
			AutoButtonColor = false,
			[React.Event.Activated] = function()
				UISound.play("confirm")
				ConsoleStore.setTab(id)
			end,
			[React.Event.MouseEnter] = function(button: TextButton)
				button.TextColor3 = theme.color.textPrimary
			end,
			[React.Event.MouseLeave] = function(button: TextButton)
				button.TextColor3 = if id == ConsoleStore.get().tab then theme.color.textPrimary else theme.color.textMuted
			end,
		}, {
			Padding = Controls.padding(6),
			Mark = if active
				then e("Frame", {
					Size = UDim2.new(1, 0, 0, 2),
					AnchorPoint = Vector2.new(0, 1),
					Position = UDim2.fromScale(0, 1),
					BackgroundColor3 = theme.color.accent,
					BorderSizePixel = 0,
				})
				else nil,
		})
	end
	return e("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = props.layoutOrder,
	}, {
		Row = e("Frame", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
		}, children),
		Hairline = e("Frame", {
			Size = UDim2.new(1, 0, 0, 1),
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			BackgroundColor3 = theme.color.stroke,
			BackgroundTransparency = 0.7,
			BorderSizePixel = 0,
		}),
	})
end

-- A count of client warnings and errors logged while the console was closed, at the screen's edge.
local function UnreadBadge(props: { count: number })
	local theme = ThemeContext.useTheme()
	return e("TextButton", {
		Text = `⚠ {props.count} new {if props.count == 1 then "warning" else "warnings"}   {TOGGLE_LABEL} console`,
		Size = UDim2.fromOffset(0, 30),
		AutomaticSize = Enum.AutomaticSize.X,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -EDGE, 0.5, 0),
		BackgroundColor3 = theme.color.surface,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		FontFace = theme.face.bodyBold,
		TextSize = Controls.SMALL,
		TextColor3 = theme.color.critical,
		[React.Event.Activated] = function()
			ConsoleStore.setOpen(true)
			ConsoleStore.setTab("log")
			ConsoleStore.setLogView("output")
		end,
	}, {
		Padding = Controls.padding(10),
		Stroke = e("UIStroke", {
			Color = theme.color.critical,
			Transparency = 0.2,
			Thickness = 1,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
	})
end

local function DevConsole()
	local theme = ThemeContext.useTheme()
	local snapshot = useConsole()
	local rootRef = React.useRef(nil :: Frame?)
	local everOpened, setEverOpened = React.useState(snapshot.open)
	local visited, setVisited = React.useState({ [snapshot.tab] = true } :: { [string]: boolean })

	React.useEffect(function()
		ConsoleStore.start()
		local toggle = UserInputService.InputBegan:Connect(function(input)
			if input.KeyCode ~= TOGGLE_KEY then
				return
			end
			-- Typing elsewhere (chat) keeps its backquote; typing in the console closes it.
			local focused = UserInputService:GetFocusedTextBox()
			local root = rootRef.current
			if focused and not (root and focused:IsDescendantOf(root)) then
				return
			end
			if focused then
				focused:ReleaseFocus()
			end
			ConsoleStore.toggle()
		end)
		local messages = LogService.MessageOut:Connect(function(message, messageType)
			if messageType == Enum.MessageType.MessageWarning or messageType == Enum.MessageType.MessageError then
				ConsoleStore.pushOutput(message, messageType == Enum.MessageType.MessageError)
			end
		end)
		return function()
			toggle:Disconnect()
			messages:Disconnect()
			InteractionStateController.setInputCaptured(CAPTURE_NAME, false)
		end
	end, {})

	React.useEffect(function()
		InteractionStateController.setInputCaptured(CAPTURE_NAME, snapshot.open)
		if snapshot.open then
			setEverOpened(true)
			UISound.play("open")
		else
			local focused = UserInputService:GetFocusedTextBox()
			local root = rootRef.current
			if focused and root and focused:IsDescendantOf(root) then
				focused:ReleaseFocus()
			end
		end
	end, { snapshot.open })

	React.useEffect(function()
		if not visited[snapshot.tab] then
			local copy = table.clone(visited)
			copy[snapshot.tab] = true
			setVisited(copy)
		end
	end, { snapshot.tab })

	local badge = if not snapshot.open and snapshot.unread > 0 then e(UnreadBadge, { count = snapshot.unread }) else nil
	if not everOpened then
		return badge
	end

	local bodies: { [string]: any } = {}
	for _, id in ipairs(ConsoleStore.TABS) do
		if visited[id] or id == snapshot.tab then
			local active = id == snapshot.tab
			bodies[id] = e("ScrollingFrame", {
				Size = UDim2.fromScale(1, 1),
				Visible = active,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				CanvasSize = UDim2.new(),
				ScrollBarThickness = 6,
				ScrollBarImageColor3 = theme.color.stroke,
				ScrollBarImageTransparency = 0.35,
				ScrollingDirection = Enum.ScrollingDirection.Y,
			}, {
				Padding = e("UIPadding", {
					PaddingTop = UDim.new(0, 8),
					PaddingBottom = UDim.new(0, 12),
				}),
				-- Inset by offset rather than padding: a scrolling frame sizes scale children from its
				-- full canvas width, so padding there would not keep content off the scroll bar. The
				-- left pixels keep outlines (drawn outside their boxes) clear of the clip.
				Inset = e("Frame", {
					Size = UDim2.new(1, -(SCROLL_GUTTER + 2), 0, 0),
					Position = UDim2.fromOffset(2, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundTransparency = 1,
				}, {
					Content = e(TAB_COMPONENTS[id], { snapshot = snapshot, active = active }),
				}),
			})
		end
	end

	-- GameUI ignores the top bar's inset, so the dock starts below it, clear of the core buttons and
	-- the player list there.
	local top = GuiService:GetGuiInset().Y + EDGE

	return e("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, {
		Badge = badge,
		Dock = e("Frame", {
			ref = rootRef,
			Visible = snapshot.open,
			Size = UDim2.new(DOCK_WIDTH_SCALE, 0, 1, -(top + EDGE)),
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -EDGE, 0, top),
			-- Nearly solid: it sits over live gameplay and HUD bars, which would otherwise show through
			-- the text.
			BackgroundColor3 = theme.color.surface,
			BackgroundTransparency = 0.04,
			BorderSizePixel = 0,
			Active = true,
		}, {
			Width = e("UISizeConstraint", {
				MinSize = Vector2.new(DOCK_MIN_WIDTH, 0),
				MaxSize = Vector2.new(DOCK_MAX_WIDTH, math.huge),
			}),
			Brackets = e(Brackets, { size = "panel" }),
			Content = e("Frame", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
			}, {
				Padding = e("UIPadding", {
					PaddingTop = UDim.new(0, 12),
					PaddingBottom = UDim.new(0, 12),
					PaddingLeft = UDim.new(0, 16),
					PaddingRight = UDim.new(0, 12),
				}),
				Layout = e("UIListLayout", {
					FillDirection = Enum.FillDirection.Vertical,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 8),
				}),
				Header = e(StatusHeader, { snapshot = snapshot, toggleKey = TOGGLE_LABEL, layoutOrder = 1 }),
				Tabs = e(TabStrip, { active = snapshot.tab, layoutOrder = 2 }),
				Body = e("Frame", {
					Size = UDim2.fromScale(1, 0),
					BackgroundTransparency = 1,
					LayoutOrder = 3,
				}, {
					Flex = e("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill }),
					Tabs = e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, bodies),
				}),
				CommandBar = e(CommandBar, { snapshot = snapshot, layoutOrder = 4 }),
			}),
		}),
	})
end

return DevConsole
