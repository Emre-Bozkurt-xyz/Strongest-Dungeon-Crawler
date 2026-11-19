--!strict
-- The strip along the console's foot: whose save is in use on the left, the scenario and stage on
-- the right.
--
-- The save matters most. On a preset the player's real save is set aside and nothing they do reaches
-- it; on the real save, `give`, `xp`, `mastery` and `drop` change it for good. The two states look
-- nothing alike so neither is mistaken for the other at a glance: the real save fills the strip in
-- the red family with a warning glyph and a red rule above it, a preset is a quiet neutral strip with
-- a green dot.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ConsoleStore = require(script.Parent.ConsoleStore)
local Controls = require(script.Parent.Controls)
local Glyphs = require(script.Parent.Glyphs)
local Theme = require(script.Parent.Theme)

local e = React.createElement
local color = Theme.color
local size = Theme.size

local HEIGHT = 30

local function StatusStrip(props: { snapshot: ConsoleStore.State, layoutOrder: number? })
	local snapshot = props.snapshot
	local dev = snapshot.devState
	local preset = snapshot.devCharacter
	local sandboxed = preset ~= ""

	local where = if dev.scenarioId ~= "" then dev.scenarioTitle else "No scenario"
	local stage = if dev.stageName ~= "" then dev.stageName else "baseplate world"

	local left: { [string]: any }
	if sandboxed then
		left = {
			Dot = e("Frame", {
				Size = UDim2.fromOffset(7, 7),
				BackgroundColor3 = color.ok,
				BorderSizePixel = 0,
				LayoutOrder = 1,
			}, { Corner = Controls.corner(Theme.radius.pill) }),
			Label = e(Controls.Text, { text = "Preset", tone = "secondary", size = size.secondary, height = HEIGHT, autoWidth = true, layoutOrder = 2 }),
			Name = e(Controls.Text, { text = preset, mono = true, size = size.monoSmall, height = HEIGHT, autoWidth = true, layoutOrder = 3 }),
			Edited = if snapshot.devCharacterEdited
				then e(Controls.Text, { text = "edited", color = color.warn, size = size.small, height = HEIGHT, autoWidth = true, layoutOrder = 4 })
				else nil,
		}
	else
		left = {
			Glyph = e(Glyphs.Glyph, { name = "warning", color = color.bad, size = 15, thickness = 1.5, layoutOrder = 1 }),
			Label = e(Controls.Text, {
				text = "Real save",
				color = color.bad,
				medium = true,
				size = size.secondary,
				height = HEIGHT,
				autoWidth = true,
				layoutOrder = 2,
			}),
			Note = e(Controls.Text, {
				text = "changes are permanent",
				color = color.badMuted,
				size = size.small,
				height = HEIGHT,
				autoWidth = true,
				layoutOrder = 3,
			}),
		}
	end

	return e("Frame", {
		Size = UDim2.new(1, 0, 0, HEIGHT),
		BackgroundColor3 = if sandboxed then color.raised else color.badSurface,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder,
	}, {
		Rule = e("Frame", {
			Size = UDim2.new(1, 0, 0, 1),
			BackgroundColor3 = if sandboxed then color.divider else color.badEdge,
			BorderSizePixel = 0,
		}),
		Content = e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, {
			Padding = Controls.padding(12),
			Layout = Controls.list(Enum.FillDirection.Horizontal, 8),
			Left = e("Frame", {
				Size = UDim2.fromOffset(0, HEIGHT),
				AutomaticSize = Enum.AutomaticSize.X,
				BackgroundTransparency = 1,
				LayoutOrder = 1,
			}, Controls.mergeInto({ Layout = Controls.list(Enum.FillDirection.Horizontal, 8) }, left)),
			Where = e(Controls.Text, {
				text = `{where} · {stage}`,
				color = if sandboxed then color.secondary else color.badMuted,
				size = size.small,
				height = HEIGHT,
				fill = true,
				alignX = Enum.TextXAlignment.Right,
				layoutOrder = 2,
			}),
		}),
	})
end

return StatusStrip
