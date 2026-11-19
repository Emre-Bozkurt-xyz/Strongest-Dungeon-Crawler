--!strict
-- What the console is acting on, always in view: the scenario, the stage and the character.
--
-- The character line matters most. On a preset the player's real save is set aside and nothing they
-- do reaches it; on the real save, `give`, `xp`, `mastery` and `drop` change it for good. The two
-- states look nothing alike, so neither can be mistaken for the other at a glance: a preset is a
-- quiet outlined line, the real save a solid red band.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ThemeContext = require(script.Parent.Parent.Parent.hooks.ThemeContext)
local ConsoleStore = require(script.Parent.ConsoleStore)
local Controls = require(script.Parent.Controls)

local e = React.createElement

local LABEL_WIDTH = 104

local function Line(props: { label: string, layoutOrder: number, children: any })
	local theme = ThemeContext.useTheme()
	local content: { [string]: any } = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 8),
		}),
	}
	for key, child in pairs(props.children) do
		content[key] = child
	end
	return e("Frame", {
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundTransparency = 1,
		LayoutOrder = props.layoutOrder,
	}, {
		Label = e(Controls.Label, {
			text = props.label,
			bold = true,
			size = Controls.SMALL,
			height = 28,
			width = UDim.new(0, LABEL_WIDTH),
			color = theme.color.textMuted,
		}),
		Content = e("Frame", {
			Size = UDim2.new(1, -LABEL_WIDTH, 1, 0),
			Position = UDim2.fromOffset(LABEL_WIDTH, 0),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
		}, content),
	})
end

local function StatusHeader(props: { snapshot: ConsoleStore.State, toggleKey: string, layoutOrder: number? })
	local theme = ThemeContext.useTheme()
	local snapshot = props.snapshot
	local dev = snapshot.devState
	local preset = snapshot.devCharacter
	local sandboxed = preset ~= ""

	local character: any
	if sandboxed then
		character = e("Frame", {
			Size = UDim2.new(1, 0, 0, 34),
			BackgroundColor3 = theme.color.success,
			BackgroundTransparency = 0.9,
			BorderSizePixel = 0,
			LayoutOrder = 4,
		}, {
			Stroke = e("UIStroke", {
				Color = theme.color.success,
				Transparency = 0.35,
				Thickness = 1,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			}),
			Padding = Controls.padding(10),
			Row = e(Controls.Row, { gap = 10, height = 34 }, {
				Tag = e(Controls.Label, {
					text = "PRESET",
					bold = true,
					size = Controls.SMALL,
					height = 34,
					width = UDim.new(0, 64),
					color = theme.color.success,
					layoutOrder = 1,
				}),
				Name = e(Controls.Label, {
					text = preset,
					mono = true,
					size = 18,
					height = 34,
					width = UDim.new(0, 0),
					fill = true,
					layoutOrder = 2,
				}),
				Note = e(Controls.Label, {
					text = "sandboxed · real save untouched",
					size = Controls.SMALL,
					height = 34,
					width = UDim.new(0, 250),
					alignX = Enum.TextXAlignment.Right,
					color = theme.color.textMuted,
					layoutOrder = 3,
				}),
			}),
		})
	else
		character = e("Frame", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = theme.color.danger,
			BackgroundTransparency = 0.12,
			BorderSizePixel = 0,
			LayoutOrder = 4,
		}, {
			Padding = Controls.padding(10, 5),
			Layout = e("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }),
			Title = e(Controls.Label, {
				text = "⚠  REAL SAVE",
				bold = true,
				size = 19,
				color = theme.color.textPrimary,
				layoutOrder = 1,
			}),
			Note = e(Controls.Label, {
				text = "give, xp, mastery and drop change your real save. Apply a preset to test safely.",
				size = Controls.SMALL,
				wrap = true,
				color = theme.color.textPrimary,
				layoutOrder = 2,
			}),
		})
	end

	return e(Controls.Stack, { gap = 2, layoutOrder = props.layoutOrder }, {
		Title = e(Controls.Row, { height = 30, layoutOrder = 1, gap = 10 }, {
			Marker = e("Frame", {
				Size = UDim2.fromOffset(8, 8),
				Rotation = 45,
				BackgroundColor3 = theme.color.stroke,
				BorderSizePixel = 0,
				LayoutOrder = 1,
			}),
			Name = e(Controls.Label, {
				text = "DEV CONSOLE",
				display = true,
				size = 20,
				height = 30,
				width = UDim.new(0, 0),
				fill = true,
				layoutOrder = 2,
			}),
			Key = e(Controls.Chip, { text = `{props.toggleKey}  close`, layoutOrder = 3 }),
		}),
		Scenario = e(Line, { label = "SCENARIO", layoutOrder = 2 }, {
			Title = e(Controls.Label, {
				text = if dev.scenarioId ~= "" then dev.scenarioTitle else "none loaded",
				bold = true,
				height = 28,
				autoWidth = true,
				color = if dev.scenarioId ~= "" then theme.color.textPrimary else theme.color.textMuted,
				layoutOrder = 1,
			}),
			Id = if dev.scenarioId ~= ""
				then e(Controls.Label, {
					text = dev.scenarioId,
					mono = true,
					size = Controls.MONO,
					height = 28,
					autoWidth = true,
					color = theme.color.textMuted,
					layoutOrder = 2,
				})
				else nil,
		}),
		Stage = e(Line, { label = "STAGE", layoutOrder = 3 }, {
			Name = e(Controls.Label, {
				text = if dev.stageName ~= "" then dev.stageName else "baseplate world",
				mono = dev.stageName ~= "",
				size = if dev.stageName ~= "" then Controls.MONO else Controls.TEXT,
				height = 28,
				color = if dev.stageName ~= "" then theme.color.textPrimary else theme.color.textMuted,
				layoutOrder = 1,
			}),
		}),
		Character = character,
	})
end

return StatusHeader
