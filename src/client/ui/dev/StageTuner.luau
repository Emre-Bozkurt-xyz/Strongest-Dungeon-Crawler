--!strict
-- Studio-only overlay for tuning the menu stage live: where the camera sits, where each panel sits,
-- and how they render, per menu view. F6 toggles it.
--
-- Values are written through DevTuningService under `UIMenu.stage`, which MenuRigRuntime re-reads
-- every frame, so a drag shows up immediately. Nothing here persists: Export prints a `stage` block
-- to paste over UIMenuConfig.stage once it looks right.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local React = require(ReplicatedStorage.Packages.React)
local UIMenuConfig = require(ReplicatedStorage.Shared.Config.UIMenuConfig)

local DevTuningService = require(script.Parent.Parent.Parent.dev.DevTuningService)
local ThemeContext = require(script.Parent.Parent.hooks.ThemeContext)
local useMenuState = require(script.Parent.Parent.hooks.useMenuState)
local MenuOrchestrator = require(script.Parent.Parent.menu.MenuOrchestrator)
local MenuRigRuntime = require(script.Parent.Parent.menu.MenuRigRuntime)
local UIRuntime = require(script.Parent.Parent.app.UIRuntime)
local DevFlags = require(script.Parent.DevFlags)
local InventoryClient = require(script.Parent.Parent.Parent.Inventory.InventoryClient)

local e = React.createElement

type View = "system" | "inventory" | "equipment"

type Field = {
	key: string,
	label: string,
	min: number,
	max: number,
	step: number,
}

local TOGGLE_KEY = Enum.KeyCode.F6
local VIEWS: { View } = { "system", "inventory", "equipment" }
local ROW_HEIGHT = 26

local CAMERA_FIELDS: { Field } = {
	{ key = "right", label = "right", min = -8, max = 8, step = 0.05 },
	{ key = "up", label = "up", min = -2, max = 6, step = 0.05 },
	{ key = "back", label = "back", min = -10, max = 12, step = 0.05 },
	{ key = "yaw", label = "yaw°", min = -90, max = 90, step = 0.5 },
	{ key = "pitch", label = "pitch°", min = -60, max = 45, step = 0.5 },
	{ key = "fov", label = "fov°", min = 20, max = 100, step = 1 },
}

local PANEL_FIELDS: { Field } = {
	{ key = "ahead", label = "ahead", min = 0.5, max = 12, step = 0.05 },
	{ key = "right", label = "right", min = -6, max = 6, step = 0.05 },
	{ key = "up", label = "up", min = -1, max = 5, step = 0.05 },
	{ key = "faceCamera", label = "face camera", min = 0, max = 1, step = 0.01 },
	{ key = "turn", label = "turn°", min = -90, max = 90, step = 0.5 },
	{ key = "tilt", label = "tilt°", min = -60, max = 60, step = 0.5 },
}

local GLOBAL_FIELDS: { Field } = {
	{ key = "panelScale", label = "panel scale", min = 0.3, max = 1.5, step = 0.01 },
	{ key = "spacing", label = "spacing", min = 0, max = 2, step = 0.05 },
	{ key = "settleRate", label = "settle /s", min = 1, max = 40, step = 0.5 },
}

local function snap(value: number, field: Field): number
	local snapped = math.round(value / field.step) * field.step
	-- Trim float noise from the step multiply so exported numbers read cleanly.
	return tonumber(string.format("%.4g", math.clamp(snapped, field.min, field.max))) :: number
end

local function readNumber(path: string): number
	local value = DevTuningService.get(path)
	return if type(value) == "number" then value else 0
end

local function writeGlobal(key: string, value: number)
	DevTuningService.set(`UIMenu.stage.{key}`, value)
	if key == "panelScale" then
		for _, panelId in ipairs(MenuRigRuntime.MENU_PANEL_IDS) do
			UIRuntime.setPanelScale(panelId, value)
		end
	end
end

local function fmt(value: number): string
	return string.format("%g", value)
end

local function exportStage(): string
	local function pose(view: View, group: string, fields: { Field }): string
		local parts = {}
		for _, field in ipairs(fields) do
			table.insert(parts, `{field.key} = {fmt(readNumber(`UIMenu.stage.views.{view}.{group}.{field.key}`))}`)
		end
		return `\{ {table.concat(parts, ", ")} \}`
	end

	local lines = {
		"\tstage = {",
		`\t\tsettleRate = {fmt(readNumber("UIMenu.stage.settleRate"))},`,
		`\t\tpanelScale = {fmt(readNumber("UIMenu.stage.panelScale"))},`,
		`\t\tspacing = {fmt(readNumber("UIMenu.stage.spacing"))},`,
		`\t\twallClearance = {fmt(readNumber("UIMenu.stage.wallClearance"))},`,
		"\t\tviews = {",
	}
	for _, view in ipairs(VIEWS) do
		table.insert(lines, `\t\t\t{view} = \{`)
		table.insert(lines, `\t\t\t\tpanel = {pose(view, "panel", PANEL_FIELDS)},`)
		table.insert(lines, `\t\t\t\tcamera = {pose(view, "camera", CAMERA_FIELDS)},`)
		table.insert(lines, "\t\t\t} :: ViewStage,")
	end
	table.insert(lines, "\t\t},")
	table.insert(lines, "\t},")
	return table.concat(lines, "\n")
end

-- Re-renders whenever anything under UIMenu.stage changes, including from /tune in chat.
local function useStageRevision(): number
	local revision, setRevision = React.useState(0)
	React.useEffect(function()
		return DevTuningService.subscribe("UIMenu.stage", function()
			setRevision(function(n)
				return n + 1
			end)
		end)
	end, {})
	return revision
end

local function SmallButton(props: { text: string, width: number?, layoutOrder: number?, onActivated: () -> () })
	local theme = ThemeContext.useTheme()
	return e("TextButton", {
		Text = props.text,
		Size = UDim2.fromOffset(props.width or ROW_HEIGHT, ROW_HEIGHT - 4),
		LayoutOrder = props.layoutOrder,
		BackgroundColor3 = theme.color.surfaceRaised,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		Font = theme.font.heading,
		TextSize = 14,
		TextColor3 = theme.color.textPrimary,
		[React.Event.Activated] = props.onActivated,
	}, {
		Corner = e("UICorner", { CornerRadius = UDim.new(0, 4) }),
	})
end

local function Slider(props: { value: number, field: Field, onChange: (number) -> () })
	local theme = ThemeContext.useTheme()
	local trackRef = React.useRef(nil :: Frame?)
	local dragging, setDragging = React.useState(false)
	-- The drag connections outlive the render that made them, so they read the latest callback.
	local onChangeRef = React.useRef(props.onChange)
	onChangeRef.current = props.onChange

	local field = props.field
	local function setFromX(x: number)
		local track = trackRef.current
		if not track or track.AbsoluteSize.X <= 0 then
			return
		end
		local ratio = math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
		onChangeRef.current(snap(field.min + ratio * (field.max - field.min), field))
	end

	React.useEffect(function()
		if not dragging then
			return
		end
		local moved = UserInputService.InputChanged:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseMovement then
				setFromX(input.Position.X)
			end
		end)
		local ended = UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				setDragging(false)
			end
		end)
		return function()
			moved:Disconnect()
			ended:Disconnect()
		end
	end, { dragging })

	local ratio = math.clamp((props.value - field.min) / (field.max - field.min), 0, 1)

	return e("Frame", {
		Size = UDim2.fromOffset(0, 8),
		BackgroundColor3 = theme.color.gaugeTrack,
		BorderSizePixel = 0,
		LayoutOrder = 3,
		Active = true,
		ref = trackRef,
		[React.Event.InputBegan] = function(_rbx: Frame, input: InputObject)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				setDragging(true)
				setFromX(input.Position.X)
			end
		end,
	}, {
		Flex = e("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill }),
		Corner = e("UICorner", { CornerRadius = UDim.new(1, 0) }),
		Fill = e("Frame", {
			Size = UDim2.fromScale(ratio, 1),
			BackgroundColor3 = theme.color.accent,
			BorderSizePixel = 0,
		}, {
			Corner = e("UICorner", { CornerRadius = UDim.new(1, 0) }),
		}),
		Knob = e("Frame", {
			Size = UDim2.fromOffset(14, 14),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(ratio, 0.5),
			BackgroundColor3 = theme.color.textPrimary,
			BorderSizePixel = 0,
		}, {
			Corner = e("UICorner", { CornerRadius = UDim.new(1, 0) }),
		}),
	})
end

local function TuneRow(props: { field: Field, value: number, layoutOrder: number, onChange: (number) -> () })
	local theme = ThemeContext.useTheme()
	local field = props.field

	return e("Frame", {
		Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
		BackgroundTransparency = 1,
		LayoutOrder = props.layoutOrder,
	}, {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 6),
		}),
		Label = e("TextLabel", {
			Text = field.label,
			Size = UDim2.new(0, 92, 1, 0),
			LayoutOrder = 1,
			BackgroundTransparency = 1,
			Font = theme.font.body,
			TextSize = 15,
			TextColor3 = theme.color.textMuted,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		Minus = e(SmallButton, {
			text = "−",
			layoutOrder = 2,
			onActivated = function()
				props.onChange(snap(props.value - field.step, field))
			end,
		}),
		Slider = e(Slider, { value = props.value, field = field, onChange = props.onChange }),
		Plus = e(SmallButton, {
			text = "+",
			layoutOrder = 4,
			onActivated = function()
				props.onChange(snap(props.value + field.step, field))
			end,
		}),
		Value = e("TextBox", {
			Text = fmt(props.value),
			Size = UDim2.new(0, 58, 1, -4),
			LayoutOrder = 5,
			BackgroundColor3 = theme.color.surfaceRaised,
			BorderSizePixel = 0,
			ClearTextOnFocus = false,
			Font = theme.font.body,
			TextSize = 15,
			TextColor3 = theme.color.textPrimary,
			[React.Event.FocusLost] = function(box: TextBox)
				local typed = tonumber(box.Text)
				if typed then
					-- Typed values are taken as given, beyond the slider's range if need be.
					props.onChange(typed)
				else
					box.Text = fmt(props.value)
				end
			end,
		}, {
			Corner = e("UICorner", { CornerRadius = UDim.new(0, 4) }),
		}),
	})
end

local function SectionTitle(props: { text: string, layoutOrder: number })
	local theme = ThemeContext.useTheme()
	return e("TextLabel", {
		Text = props.text,
		Size = UDim2.new(1, 0, 0, 22),
		LayoutOrder = props.layoutOrder,
		BackgroundTransparency = 1,
		Font = theme.font.heading,
		TextSize = 16,
		TextColor3 = theme.color.textHeading,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
end

local function StageTuner()
	local theme = ThemeContext.useTheme()
	local open, setOpen = React.useState(false)
	local menu = useMenuState()
	local menuView: View = menu.modal.view
	local editing, setEditing = React.useState(menuView)
	local exported, setExported = React.useState("")
	local dockRight, setDockRight = React.useState(false)
	useStageRevision()

	React.useEffect(function()
		local conn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
			if not gameProcessed and input.KeyCode == TOGGLE_KEY then
				setOpen(function(was)
					return not was
				end)
			end
		end)
		return function()
			conn:Disconnect()
		end
	end, {})

	-- Follow the menu: switching views in game switches what is being edited.
	React.useEffect(function()
		setEditing(menuView)
	end, { menuView })

	if not open then
		return nil
	end

	local children: { [string]: any } = {
		Layout = e("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 4),
		}),
		Padding = e("UIPadding", {
			PaddingTop = UDim.new(0, 10),
			PaddingBottom = UDim.new(0, 10),
			PaddingLeft = UDim.new(0, 12),
			PaddingRight = UDim.new(0, 12),
		}),
	}
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	children.Title = e(SectionTitle, {
		text = if menu.modal.open then "Menu stage (F6)" else "Menu stage (F6) — open a view to see changes",
		layoutOrder = nextOrder(),
	})

	-- View tabs. Picking one also opens the menu on it, so the change is visible straight away.
	local tabs: { [string]: any } = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 6),
		}),
	}
	-- The overlay covers whichever side of the screen the composition is not using, so it can move.
	tabs.Dock = e(SmallButton, {
		text = if dockRight then "◀ dock" else "dock ▶",
		width = 70,
		layoutOrder = 99,
		onActivated = function()
			setDockRight(not dockRight)
		end,
	})
	for index, view in ipairs(VIEWS) do
		tabs[view] = e(SmallButton, {
			text = if view == editing then `[{view}]` else view,
			width = 100,
			layoutOrder = index,
			onActivated = function()
				setEditing(view)
				if menu.modal.open then
					MenuOrchestrator.setView(view :: any)
				else
					MenuOrchestrator.open(view :: any)
				end
			end,
		})
	end
	children.Tabs = e("Frame", {
		Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
		BackgroundTransparency = 1,
		LayoutOrder = nextOrder(),
	}, tabs)

	local function addFields(prefix: string, fields: { Field }, write: (Field, number) -> ())
		for _, field in ipairs(fields) do
			children[`{prefix}_{field.key}`] = e(TuneRow, {
				field = field,
				value = readNumber(`{prefix}.{field.key}`),
				layoutOrder = nextOrder(),
				onChange = function(value: number)
					write(field, value)
				end,
			})
		end
	end

	local viewPrefix = `UIMenu.stage.views.{editing}`
	children.CameraTitle = e(SectionTitle, { text = `Camera — {editing}`, layoutOrder = nextOrder() })
	addFields(`{viewPrefix}.camera`, CAMERA_FIELDS, function(field, value)
		DevTuningService.set(`{viewPrefix}.camera.{field.key}`, value)
	end)
	children.PanelTitle = e(SectionTitle, { text = `Panel — {editing}`, layoutOrder = nextOrder() })
	addFields(`{viewPrefix}.panel`, PANEL_FIELDS, function(field, value)
		DevTuningService.set(`{viewPrefix}.panel.{field.key}`, value)
	end)
	children.GlobalTitle = e(SectionTitle, { text = "All views", layoutOrder = nextOrder() })
	addFields("UIMenu.stage", GLOBAL_FIELDS, function(field, value)
		writeGlobal(field.key, value)
	end)

	local actions: { [string]: any } = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 6),
			Wraps = true,
		}),
		CopyToAll = e(SmallButton, {
			text = "Copy to all",
			width = 100,
			layoutOrder = 1,
			onActivated = function()
				for _, view in ipairs(VIEWS) do
					if view ~= editing then
						for _, group in ipairs({ { "camera", CAMERA_FIELDS }, { "panel", PANEL_FIELDS } }) do
							for _, field in ipairs(group[2] :: { Field }) do
								local key = `{group[1]}.{field.key}`
								DevTuningService.set(`UIMenu.stage.views.{view}.{key}`, readNumber(`{viewPrefix}.{key}`))
							end
						end
					end
				end
			end,
		}),
		ResetView = e(SmallButton, {
			text = "Reset view",
			width = 90,
			layoutOrder = 2,
			onActivated = function()
				DevTuningService.reset(viewPrefix)
			end,
		}),
		ResetAll = e(SmallButton, {
			text = "Reset all",
			width = 80,
			layoutOrder = 3,
			onActivated = function()
				DevTuningService.reset("UIMenu.stage")
				for _, panelId in ipairs(MenuRigRuntime.MENU_PANEL_IDS) do
					UIRuntime.setPanelScale(panelId, UIMenuConfig.stage.panelScale)
				end
			end,
		}),
		Export = e(SmallButton, {
			text = "Export",
			width = 70,
			layoutOrder = 4,
			onActivated = function()
				local text = exportStage()
				setExported(text)
				print("[StageTuner] Paste over UIMenuConfig.stage:\n" .. text)
			end,
		}),
		-- The style tile renders on the System panel, so turning it on also opens that view.
		StyleTile = e(SmallButton, {
			text = "Tile",
			width = 60,
			layoutOrder = 5,
			onActivated = function()
				local showing = not DevFlags.get("styleTile")
				DevFlags.set("styleTile", showing)
				if showing then
					setEditing("system")
					if menu.modal.open then
						MenuOrchestrator.setView("system")
					else
						MenuOrchestrator.open("system")
					end
				end
			end,
		}),
		-- Inspects the first bagged item, so the inspect card can be checked without a click on a world
		-- panel.
		Inspect = e(SmallButton, {
			text = "Inspect",
			width = 70,
			layoutOrder = 6,
			onActivated = function()
				local inventory = InventoryClient.getInventory()
				local uid = inventory and inventory.slots[1]
				if not uid then
					warn("[StageTuner] Nothing in the first bag slot to inspect")
					return
				end
				if menu.modal.open then
					MenuOrchestrator.setView("inventory")
				else
					MenuOrchestrator.open("inventory")
				end
				MenuOrchestrator.setInspect("inventory", { uid = uid })
			end,
		}),
	}
	children.Actions = e("Frame", {
		Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = nextOrder(),
	}, actions)

	if exported ~= "" then
		-- Selectable so it can be copied with Ctrl+A / Ctrl+C; Roblox has no clipboard API.
		children.Exported = e("TextBox", {
			Text = exported,
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = nextOrder(),
			BackgroundColor3 = theme.color.surfaceRaised,
			BorderSizePixel = 0,
			ClearTextOnFocus = false,
			TextEditable = false,
			MultiLine = true,
			TextWrapped = false,
			Font = Enum.Font.Code,
			TextSize = 12,
			TextColor3 = theme.color.textPrimary,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
		})
	end

	return e("ScrollingFrame", {
		Size = UDim2.new(0, 470, 1, -140),
		AnchorPoint = Vector2.new(if dockRight then 1 else 0, 0),
		Position = if dockRight then UDim2.new(1, -16, 0, 70) else UDim2.fromOffset(16, 70),
		BackgroundColor3 = theme.color.surface,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Active = true,
	}, children)
end

return StageTuner
