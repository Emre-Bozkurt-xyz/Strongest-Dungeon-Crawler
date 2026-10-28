--!strict
-- The node tooltip (docs/planning/mastery-mind-space.md, "Interaction"): hovering a node previews
-- it, clicking pins it, and clicking the pinned node again takes its action.
--
-- Clean and complete: the node's name and kind, a lore line for the nodes that have one, every
-- effect with its live numbers (now, at Mastered, and the attuned bonus where it applies), what a
-- locked node takes, the named combination it would make, and the action line.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local MasteryTracks = require(ReplicatedStorage.Shared.progression.MasteryTracks)
local MasteryTree = require(ReplicatedStorage.Shared.progression.MasteryTree)
local MasteryTrees = require(ReplicatedStorage.Shared.progression.MasteryTrees)
local NodeEffects = require(ReplicatedStorage.Shared.progression.NodeEffects)
local EffectText = require(ReplicatedStorage.Shared.progression.EffectText)

local ThemeContext = require(script.Parent.Parent.Parent.hooks.ThemeContext)

local e = React.createElement

local WIDTH = 400
local PADDING = 22
local INK = Color3.fromRGB(238, 241, 246)
local DIM = Color3.fromRGB(122, 128, 140)

local KIND_NAME: { [string]: string } = {
	passive = "PASSIVE",
	select = "SELECTABLE PASSIVE",
	attuned = "ATTUNEMENT NODE",
	form = "FORM",
	infusion = "INFUSION",
}

export type Action = {
	label: string,
	enabled: boolean,
}

export type Props = {
	node: MasteryTree.Node,
	trackId: string,
	branches: { [string]: number },
	attuned: boolean,
	pinned: boolean,
	-- What a second click does, if anything; `state` names a standing the node already has (IN USE).
	action: Action?,
	state: string?,
	-- Screen-space binding: the node's centre, and how far its art reaches from it.
	anchor: any,
	reach: number,
}

type Line = { text: string, kind: "lore" | "effect" | "grow" | "note" | "warn" }

local LINE_STYLE: { [string]: { size: number, color: Color3, transparency: number } } = {
	lore = { size = 17, color = INK, transparency = 0.3 },
	effect = { size = 18, color = INK, transparency = 0 },
	-- What an effect grows to: small and dim, under the effect it belongs to.
	grow = { size = 15, color = DIM, transparency = 0 },
	note = { size = 15, color = INK, transparency = 0.3 },
	warn = { size = 15, color = DIM, transparency = 0 },
}

local function linesFor(props: Props): { Line }
	local node = props.node
	local def = MasteryTrees.node(node.id)
	local track = MasteryTracks.get(props.trackId)
	local lines: { Line } = {}
	if node.kind ~= "passive" then
		table.insert(lines, { text = node.description, kind = "lore" })
	end

	local effects = NodeEffects.of(node.id)
	if def and effects then
		local scale = NodeEffects.scaleOf(def, props.trackId, props.branches, props.attuned)
		local growth = NodeEffects.growthOf(def, props.branches)
		local element = track ~= nil and track.family == "element"
		local maxScale = (1 + NodeEffects.GROWTH) * (if element and props.attuned then NodeEffects.ATTUNED_ELEMENT else 1)
		for _, effect in ipairs(effects) do
			table.insert(lines, { text = EffectText.describe(effect, scale), kind = "effect" })
			local notes: { string } = {}
			local atMax = EffectText.figureAt(effect, maxScale)
			if atMax and growth < 1 then
				table.insert(notes, `{atMax} when this branch is Mastered`)
			end
			if element and not props.attuned and atMax and track then
				table.insert(notes, `×{NodeEffects.ATTUNED_ELEMENT} with {track.displayName} attuned`)
			end
			if #notes > 0 then
				table.insert(lines, { text = table.concat(notes, "  ·  "), kind = "grow" })
			end
		end
	end

	local infusion = def and def.infusion
	if infusion then
		table.insert(lines, {
			text = `{math.floor(infusion.conversion * 100 + 0.5)}% of the attack's damage becomes {infusion.element}`,
			kind = "effect",
		})
		table.insert(lines, {
			text = `Costs {infusion.cost.perStep} {infusion.cost.resource} more per combo step`,
			kind = "effect",
		})
	end

	if node.kind == "form" then
		if node.attributes then
			local parts: { string } = {}
			for attribute, tier in pairs(node.attributes) do
				table.insert(parts, `{string.upper(attribute)} {string.upper(tier)}`)
			end
			table.sort(parts)
			table.insert(lines, { text = `Suits  {table.concat(parts, "  ·  ")}`, kind = "note" })
		end
		if node.unlocked and not node.shapeId then
			table.insert(lines, {
				text = if node.built then "Does not fit the weapon you hold." else "Not built yet.",
				kind = "note",
			})
		end
	end

	if node.combination then
		local other = if node.kind == "infusion" then "your current form" else "your current infusion"
		table.insert(lines, { text = `With {other}: {string.upper(node.combination)}`, kind = "note" })
	end
	if not node.unlocked and node.requirement then
		table.insert(lines, { text = node.requirement, kind = "warn" })
	end
	if node.unlocked and node.dormant and track then
		table.insert(lines, {
			text = `Dormant. Attune {track.displayName} at a shrine to wake it.`,
			kind = "warn",
		})
	end
	return lines
end

local function Tooltip(props: Props)
	local theme = ThemeContext.useTheme()
	local height, setHeight = React.useState(0)
	local node = props.node
	local lines = linesFor(props)

	local children: { [string]: any } = {
		Layout = e("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8) }),
		Padding = e("UIPadding", {
			PaddingLeft = UDim.new(0, PADDING),
			PaddingRight = UDim.new(0, PADDING),
			PaddingTop = UDim.new(0, PADDING - 4),
			PaddingBottom = UDim.new(0, PADDING - 2),
		}),
		Kind = e("TextLabel", {
			Size = UDim2.new(1, 0, 0, 12),
			BackgroundTransparency = 1,
			Text = KIND_NAME[node.kind] or string.upper(node.kind),
			FontFace = theme.face.display,
			TextSize = 11,
			TextColor3 = DIM,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = 1,
		}),
		Name = e("TextLabel", {
			Size = UDim2.new(1, 0, 0, 24),
			BackgroundTransparency = 1,
			Text = string.upper(node.displayName),
			FontFace = theme.face.display,
			TextSize = 19,
			TextColor3 = INK,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = 2,
		}),
	}
	for index, line in ipairs(lines) do
		local look = LINE_STYLE[line.kind]
		children[`Line{index}`] = e("TextLabel", {
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.fromScale(1, 0),
			BackgroundTransparency = 1,
			Text = line.text,
			FontFace = if line.kind == "warn" or line.kind == "note" then theme.face.bodyBold else theme.face.body,
			TextSize = look.size,
			TextColor3 = look.color,
			TextTransparency = look.transparency,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = 10 + index,
		})
	end

	if props.action or props.state then
		local hint = if props.action and props.action.enabled
			then (if props.pinned then "CLICK AGAIN" else "CLICK TO SELECT")
			else ""
		children.Action = e("Frame", {
			Size = UDim2.new(1, 0, 0, 34),
			BackgroundTransparency = 1,
			LayoutOrder = 100,
		}, {
			Rule = e("Frame", {
				Size = UDim2.new(1, 0, 0, 1),
				BackgroundColor3 = INK,
				BackgroundTransparency = 0.86,
				BorderSizePixel = 0,
			}),
			Label = e("TextLabel", {
				Size = UDim2.new(0.65, 0, 0, 24),
				Position = UDim2.fromOffset(0, 10),
				BackgroundTransparency = 1,
				Text = if props.action then props.action.label else (props.state or ""),
				FontFace = theme.face.display,
				TextSize = 13,
				TextColor3 = INK,
				TextTransparency = if props.action and props.action.enabled then 0 else 0.45,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			Hint = e("TextLabel", {
				Size = UDim2.new(0.35, 0, 0, 24),
				Position = UDim2.new(1, 0, 0, 10),
				AnchorPoint = Vector2.new(1, 0),
				BackgroundTransparency = 1,
				Text = hint,
				FontFace = theme.face.display,
				TextSize = 10,
				TextColor3 = DIM,
				TextXAlignment = Enum.TextXAlignment.Right,
			}),
		})
	end

	-- Beside the node, flipped to its left when the right edge would cut it off, and kept on screen.
	local position = props.anchor:map(function(anchor: Vector2)
		local camera = workspace.CurrentCamera
		local view = if camera then camera.ViewportSize else Vector2.new(1920, 1080)
		local x = anchor.X + props.reach + 18
		if x + WIDTH > view.X - 24 then
			x = anchor.X - props.reach - 18 - WIDTH
		end
		local y = math.clamp(anchor.Y - 40, 24, math.max(24, view.Y - height - 24))
		return UDim2.fromOffset(x, y)
	end)

	return e("Frame", {
		Size = UDim2.fromOffset(WIDTH, height),
		Position = position,
		BackgroundColor3 = Color3.fromRGB(6, 7, 10),
		BackgroundTransparency = 0.06,
		BorderSizePixel = 0,
		ZIndex = 20,
	}, {
		Stroke = e("UIStroke", {
			Color = INK,
			Thickness = 1,
			Transparency = if props.pinned then 0.68 else 0.86,
		}),
		Content = e("Frame", {
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.fromScale(1, 0),
			BackgroundTransparency = 1,
			[React.Change.AbsoluteSize] = function(rbx: Frame)
				setHeight(rbx.AbsoluteSize.Y)
			end,
		}, children),
	})
end

return Tooltip
