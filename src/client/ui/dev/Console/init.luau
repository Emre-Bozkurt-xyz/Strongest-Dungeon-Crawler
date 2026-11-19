--!strict
-- The in-game developer console (dev sessions only; ScreenRegistry mounts it when
-- DevAccess.isEnabled()). The backquote key toggles it.
--
-- Docked to the right edge at a fixed width and the full height, so the game stays in view while
-- spawning, swapping characters or flipping flags; the HUD stays up beside it. While open it takes
-- the cursor and keeps gameplay input (skills, targeting) from firing, the way the menu does, through
-- a named input capture that is given back on close.
--
-- Laid out as a command palette, top to bottom: the command line (the main way in), then a narrow
-- rail of the seven tabs beside the active tab's content column, then a status strip with the save
-- in use and the scenario. Every action is a command run through DevCommandsClient (ConsoleStore);
-- the Commands tab builds a form for every registered command from its descriptor, so the console
-- never lags behind the registry. The look is the console's own (Console/Theme), not the game's.
--
-- Rendered only from the first time it is opened, then kept mounted and hidden, so typed text, open
-- forms and the tab survive closing it; ConsoleStore holds the rest across respawns.

local GuiService = game:GetService("GuiService")
local LogService = game:GetService("LogService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local React = require(ReplicatedStorage.Packages.React)
local ui = script.Parent.Parent
local UISound = require(ui.UISound)
local InteractionStateController = require(ui.Parent.input.InteractionStateController)

local ConsoleStore = require(script.ConsoleStore)
local useConsole = require(script.useConsole)
local Controls = require(script.Controls)
local Glyphs = require(script.Glyphs)
local Theme = require(script.Theme)
local StatusStrip = require(script.StatusStrip)
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
-- Name (the rail's tooltip) and the short label drawn if a tab has no glyph.
local TAB_INFO: { [string]: { label: string, short: string } } = {
	scenarios = { label = "Scenarios", short = "Scn" },
	character = { label = "Character", short = "Chr" },
	world = { label = "World", short = "Wld" },
	debug = { label = "Debug", short = "Dbg" },
	commands = { label = "Commands", short = "Cmd" },
	log = { label = "Log", short = "Log" },
	inspect = { label = "Inspect", short = "Ins" },
}

local e = React.createElement
local color = Theme.color

-- Backquote: Roblox core binds nothing to it, the game binds nothing to it, and it is where a
-- console key usually is. F-keys are not used because core claims several of them.
local TOGGLE_KEY = Enum.KeyCode.Backquote
local TOGGLE_LABEL = "`"
local CAPTURE_NAME = "DevConsole"

local DOCK_WIDTH_SCALE = 0.34
local DOCK_MIN_WIDTH = 460
local DOCK_MAX_WIDTH = 600
local RAIL_WIDTH = 52
local EDGE = 8

local function Rail(props: { active: string, layoutOrder: number? })
	local children: { [string]: any } = {
		Layout = Controls.list(Enum.FillDirection.Vertical, 6, { HorizontalAlignment = Enum.HorizontalAlignment.Center }),
		Padding = Controls.padding(0, nil, 10, 10),
	}
	for index, id in ipairs(ConsoleStore.TABS) do
		local info = TAB_INFO[id]
		children[id] = e(Controls.RailItem, {
			label = info.label,
			short = info.short,
			glyph = id,
			active = id == props.active,
			layoutOrder = index,
			onActivated = function()
				ConsoleStore.setTab(id)
				ConsoleStore.focusInput()
			end,
		})
	end
	return e("Frame", {
		Size = UDim2.new(0, RAIL_WIDTH, 1, 0),
		BackgroundTransparency = 1,
		LayoutOrder = props.layoutOrder,
		-- Above the content column, so the tooltips beside the rail draw over it.
		ZIndex = 5,
	}, {
		Items = e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, children),
		Rule = e("Frame", {
			Size = UDim2.new(0, 1, 1, 0),
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			BackgroundColor3 = color.divider,
			BorderSizePixel = 0,
		}),
	})
end

-- A count of client warnings and errors logged while the console was closed, at the screen's edge.
local function UnreadBadge(props: { count: number })
	return e("TextButton", {
		Text = "",
		Size = UDim2.fromOffset(0, 32),
		AutomaticSize = Enum.AutomaticSize.X,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -EDGE, 0.5, 0),
		BackgroundColor3 = color.badSurface,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		[React.Event.Activated] = function()
			ConsoleStore.setOpen(true)
			ConsoleStore.setTab("log")
			ConsoleStore.setLogView("output")
		end,
	}, {
		Padding = Controls.padding(12),
		Corner = Controls.corner(Theme.radius.large),
		Stroke = Controls.outline(color.badEdge),
		Layout = Controls.list(Enum.FillDirection.Horizontal, 8),
		Glyph = e(Glyphs.Glyph, { name = "warning", color = color.bad, size = 15, layoutOrder = 1 }),
		Text = e(Controls.Text, {
			text = `{props.count} new {if props.count == 1 then "warning" else "warnings"}`,
			color = color.bad,
			medium = true,
			size = Theme.size.secondary,
			height = 32,
			autoWidth = true,
			layoutOrder = 2,
		}),
		Key = e(Controls.Kbd, { text = TOGGLE_LABEL, layoutOrder = 3 }),
	})
end

local function DevConsole()
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
		-- A click anywhere in the console that does not land in another field hands the keyboard back to
		-- the command line, so Up/Down and Enter keep acting on the selection after pressing a button.
		local clicks = UserInputService.InputEnded:Connect(function(input)
			local root = rootRef.current
			if input.UserInputType ~= Enum.UserInputType.MouseButton1 or not (root and root.Visible) then
				return
			end
			local position = input.Position
			local origin, extent = root.AbsolutePosition, root.AbsoluteSize
			local inside = position.X >= origin.X
				and position.X <= origin.X + extent.X
				and position.Y >= origin.Y
				and position.Y <= origin.Y + extent.Y
			if not inside then
				return
			end
			-- A text field may only take focus after this runs, so a click that pressed one is
			-- recognised by the press rather than by what has focus yet.
			if Controls.fieldPressedRecently() then
				return
			end
			task.defer(ConsoleStore.focusInput)
		end)
		local messages = LogService.MessageOut:Connect(function(message, messageType)
			if messageType == Enum.MessageType.MessageWarning or messageType == Enum.MessageType.MessageError then
				ConsoleStore.pushOutput(message, messageType == Enum.MessageType.MessageError)
			end
		end)
		return function()
			toggle:Disconnect()
			clicks:Disconnect()
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
			bodies[id] = e("Frame", {
				Size = UDim2.fromScale(1, 1),
				Visible = active,
				BackgroundTransparency = 1,
			}, {
				Content = e(TAB_COMPONENTS[id], { snapshot = snapshot, active = active }),
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
			Size = UDim2.new(DOCK_WIDTH_SCALE, 0, 1, -top),
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, top),
			-- Solid: it sits over live gameplay and HUD bars, which would otherwise show through the text.
			BackgroundColor3 = color.panel,
			BorderSizePixel = 0,
			Active = true,
		}, {
			Width = e("UISizeConstraint", {
				MinSize = Vector2.new(DOCK_MIN_WIDTH, 0),
				MaxSize = Vector2.new(DOCK_MAX_WIDTH, math.huge),
			}),
			Edge = e("Frame", {
				Size = UDim2.new(0, 1, 1, 0),
				BackgroundColor3 = color.edge,
				BorderSizePixel = 0,
				ZIndex = 2,
			}),
			TopEdge = e("Frame", {
				Size = UDim2.new(1, 0, 0, 1),
				BackgroundColor3 = color.edge,
				BorderSizePixel = 0,
				ZIndex = 2,
			}),
			Column = e("Frame", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
			}, {
				Layout = Controls.list(Enum.FillDirection.Vertical, 0),
				CommandBar = e(CommandBar, { snapshot = snapshot, layoutOrder = 1 }),
				Rule = e(Controls.Divider, { layoutOrder = 2 }),
				Main = e("Frame", {
					Size = UDim2.fromScale(1, 0),
					BackgroundTransparency = 1,
					LayoutOrder = 3,
				}, {
					Flex = e("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill }),
					Layout = Controls.list(Enum.FillDirection.Horizontal, 0, { VerticalAlignment = Enum.VerticalAlignment.Top }),
					Rail = e(Rail, { active = snapshot.tab, layoutOrder = 1 }),
					Body = e("Frame", {
						Size = UDim2.fromScale(0, 1),
						BackgroundTransparency = 1,
						LayoutOrder = 2,
					}, {
						Flex = e("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill }),
						Tabs = e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, bodies),
					}),
				}),
				Status = e(StatusStrip, { snapshot = snapshot, layoutOrder = 4 }),
			}),
			Overlay = e("Frame", {
				ref = Controls.setOverlay,
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				ZIndex = 100,
			}),
		}),
	})
end

return DevConsole
