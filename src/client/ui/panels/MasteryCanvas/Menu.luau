--!strict
-- The mastery menu: every mastery as a box floating in the mind-space, fighting styles above and
-- elements below (docs/planning/mastery-mind-space.md, "Structure"). Choosing a box zooms into its
-- tree; at a shrine it attunes the mastery instead.
--
-- A box carries only what helps a glance: the emblem, the name, the level and its progress, and
-- what the player uses from it. An attuned mastery wears embroidery at its corners; a fighting style
-- that is not attuned is dimmed, since only its root form works. The header holds the limits that
-- apply across every mastery: attunement slots and selectable passive slots.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local MasteryTracks = require(ReplicatedStorage.Shared.progression.MasteryTracks)
local MasteryTrees = require(ReplicatedStorage.Shared.progression.MasteryTrees)
local MasteryXP = require(ReplicatedStorage.Shared.progression.MasteryXP)
local MasteryArt = require(ReplicatedStorage.Shared.progression.MasteryArt)

local ThemeContext = require(script.Parent.Parent.Parent.hooks.ThemeContext)
local useSpring = require(script.Parent.Parent.Parent.hooks.useSpring)
local Glyph = require(script.Parent.Parent.Parent.components.Glyph)
local UISound = require(script.Parent.Parent.Parent.UISound)
local ProgressionClient = require(script.Parent.Parent.Parent.Parent.Progression.ProgressionClient)
local Burst = require(script.Parent.Burst)

local e = React.createElement

local BOX = Vector2.new(300, 220)
local GAP = 24
local WIDTH = BOX.X * 4 + GAP * 3
-- Placeholder boxes after the elements, so the row reads as a set still being discovered.
local UNFELT = 2

local INK = Color3.fromRGB(238, 241, 246)
local DIM = Color3.fromRGB(138, 144, 155)
local FAINT = Color3.fromRGB(38, 42, 51)

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function join(base: { [string]: any }, extra: { [string]: any }): { [string]: any }
	local out = table.clone(base)
	for key, value in pairs(extra) do
		out[key] = value
	end
	return out
end

-- Embroidery on an attuned box: the four corner pieces, each pinned just outside its corner.
local CORNER_SIZE = 46
local CORNER_OUTSET = 9

local function cornerPieces(): { [string]: any }?
	local pieces = MasteryArt.corners()
	if not pieces then
		return nil
	end
	local out: { [string]: any } = {}
	for index, piece in ipairs(pieces) do
		local right = index == 2 or index == 4
		local bottom = index >= 3
		out[`Corner{index}`] = e(
			"ImageLabel",
			join(MasteryArt.imageProps(piece), {
				Size = UDim2.fromOffset(CORNER_SIZE, CORNER_SIZE),
				Position = UDim2.new(
					if right then 1 else 0,
					if right then CORNER_OUTSET else -CORNER_OUTSET,
					if bottom then 1 else 0,
					if bottom then CORNER_OUTSET else -CORNER_OUTSET
				),
				AnchorPoint = Vector2.new(if right then 1 else 0, if bottom then 1 else 0),
				BackgroundTransparency = 1,
				ImageColor3 = INK,
				ScaleType = Enum.ScaleType.Fit,
			})
		)
	end
	return out
end

-- What the player uses from a mastery: the form in use for the held weapon, or the infusion in use.
local function usingFrom(track: MasteryTracks.Track, context: string): (string?, string?)
	local snapshot = ProgressionClient.get()
	if not snapshot then
		return nil, nil
	end
	if track.family == "element" then
		local node, tree = MasteryTrees.node(snapshot.infusion)
		if node and tree and tree.track == track.id then
			return "INFUSION", node.displayName
		end
		return nil, nil
	end
	local held = MasteryTracks.forContext(context)
	if not held or held.id ~= track.id then
		return nil, nil
	end
	local shapeId = snapshot.shapes[context]
	local node = if shapeId and shapeId ~= "" then MasteryTrees.nodeForShape(shapeId) else nil
	if not node then
		-- No choice made: the weapon's default form, which is this track's root.
		local tree = MasteryTrees.get(track.id)
		for _, candidate in ipairs(if tree then tree.nodes else {}) do
			if candidate.kind == "form" and candidate.branch == "trunk" and candidate.rank == 0 then
				node = candidate
			end
		end
	end
	return "FORM", if node then node.displayName else nil
end

local function fitScale(size: Vector2): number
	local camera = workspace.CurrentCamera
	local view = if camera then camera.ViewportSize else Vector2.new(1920, 1080)
	return math.min(1, (view.X - 96) / size.X, (view.Y - 200) / size.Y)
end

local function Pip(props: { filled: boolean, layoutOrder: number })
	return e("Frame", {
		Size = UDim2.fromOffset(9, 9),
		Rotation = 45,
		BackgroundColor3 = INK,
		BackgroundTransparency = if props.filled then 0 else 1,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder,
	}, {
		Stroke = e("UIStroke", { Color = INK, Thickness = 1 }),
	})
end

type BoxProps = {
	track: MasteryTracks.Track,
	attuned: boolean,
	shrine: boolean,
	context: string,
	layoutOrder: number,
	-- Set when this mastery was just attuned: the box bursts once (the number tells bursts apart).
	celebrate: number?,
	onCelebrated: () -> (),
	onActivated: () -> (),
}

local function Box(props: BoxProps)
	local theme = ThemeContext.useTheme()
	local hovered, setHovered = React.useState(false)
	local hover = useSpring(if hovered then 1 else 0, theme.motion.snap)
	local track = props.track
	local dormant = track.family == "attack" and not props.attuned
	local ink = if dormant then DIM else INK

	local progress = MasteryXP.progressOf(MasteryXP.totalOf(ProgressionClient.branches(track.id)))
	local fraction = if progress.needed then math.clamp(progress.into / progress.needed, 0, 1) else 1
	local levelText = if progress.needed
		then `LV {progress.level}  ·  {math.floor(progress.into)}/{math.ceil(progress.needed)}`
		else `LV {progress.level}  ·  MAX`
	local usingKind, usingName = usingFrom(track, props.context)
	local emblem = MasteryArt.get(`mastery.{track.id}`)

	return e("TextButton", {
		Size = UDim2.fromOffset(BOX.X, BOX.Y),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = props.layoutOrder,
		[React.Event.MouseEnter] = function()
			setHovered(true)
			UISound.play("hover")
		end,
		[React.Event.MouseLeave] = function()
			setHovered(false)
		end,
		[React.Event.Activated] = props.onActivated,
	}, {
		-- The card lifts on hover; the button stays put so the pointer never slips off its edge.
		Card = e("Frame", {
			Size = UDim2.fromScale(1, 1),
			Position = hover:map(function(h: number)
				return UDim2.fromOffset(0, -3 * h)
			end),
			BackgroundColor3 = Color3.fromRGB(10, 12, 17),
			BackgroundTransparency = hover:map(function(h: number)
				return lerp(0.45, 0.3, h)
			end),
			BorderSizePixel = 0,
		}, {
			Stroke = e("UIStroke", {
				Color = INK,
				Thickness = 1,
				Transparency = hover:map(function(h: number)
					return lerp(if props.shrine then 0.7 else 0.86, 0.55, h)
				end),
			}),
			Emblem = if emblem
				then e(
					"ImageLabel",
					join(MasteryArt.imageProps(emblem), {
						Size = UDim2.fromOffset(104, 104),
						Position = UDim2.fromScale(0.5, 0.42),
						AnchorPoint = Vector2.new(0.5, 0.5),
						BackgroundTransparency = 1,
						ImageColor3 = ink,
						ScaleType = Enum.ScaleType.Fit,
					})
				)
				else e("Frame", {
					Size = UDim2.fromOffset(48, 48),
					Position = UDim2.fromScale(0.5, 0.44),
					AnchorPoint = Vector2.new(0.5, 0.5),
					BackgroundTransparency = 1,
				}, {
					Glyph = e(Glyph, { glyph = track.glyph, color = ink, thickness = 1.25 }),
				}),
			Name = e("TextLabel", {
				Size = UDim2.fromOffset(170, 28),
				Position = UDim2.new(0, 18, 1, -28),
				AnchorPoint = Vector2.new(0, 1),
				BackgroundTransparency = 1,
				Text = string.upper(track.displayName),
				FontFace = theme.face.display,
				TextSize = 21,
				TextColor3 = ink,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			Level = e("TextLabel", {
				Size = UDim2.fromOffset(180, 26),
				Position = UDim2.new(1, -18, 1, -29),
				AnchorPoint = Vector2.new(1, 1),
				BackgroundTransparency = 1,
				Text = levelText,
				FontFace = theme.face.mono,
				TextSize = 18,
				TextColor3 = INK,
				TextTransparency = 0.15,
				TextXAlignment = Enum.TextXAlignment.Right,
			}),
			Bar = e("Frame", {
				Size = UDim2.new(1, -36, 0, 1),
				Position = UDim2.new(0, 18, 1, -18),
				BackgroundColor3 = FAINT,
				BorderSizePixel = 0,
			}, {
				Fill = e("Frame", {
					Size = UDim2.new(fraction, 0, 0, 2),
					Position = UDim2.fromOffset(0, -0.5),
					BackgroundColor3 = INK,
					BorderSizePixel = 0,
				}),
			}),
			Using = if usingKind and usingName
				then e("Frame", {
					Size = UDim2.new(0.6, 0, 0, 46),
					Position = UDim2.new(1, -16, 0, 14),
					AnchorPoint = Vector2.new(1, 0),
					BackgroundTransparency = 1,
				}, {
					Kind = e("TextLabel", {
						Size = UDim2.new(1, 0, 0, 20),
						BackgroundTransparency = 1,
						Text = usingKind,
						FontFace = theme.face.bodyBold,
						TextSize = 17,
						TextColor3 = INK,
						TextXAlignment = Enum.TextXAlignment.Right,
					}),
					Name = e("TextLabel", {
						Size = UDim2.new(1, 0, 0, 24),
						Position = UDim2.fromOffset(0, 21),
						BackgroundTransparency = 1,
						Text = usingName,
						FontFace = theme.face.bodyBold,
						TextSize = 21,
						TextColor3 = INK,
						TextTransparency = 0.1,
						TextXAlignment = Enum.TextXAlignment.Right,
						TextTruncate = Enum.TextTruncate.AtEnd,
					}),
				})
				else nil,
			Corners = if props.attuned
				then e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, cornerPieces())
				else nil,
			-- Keyed by the attunement, so a second one restarts the burst rather than reusing it.
			[`Burst{props.celebrate or 0}`] = if props.celebrate
				then e(Burst, {
					position = Vector2.new(BOX.X / 2, BOX.Y * 0.42),
					strength = 1.8,
					seed = props.celebrate,
					onDone = props.onCelebrated,
				})
				else nil,
		}),
	})
end

local function UnfeltBox(props: { layoutOrder: number })
	local theme = ThemeContext.useTheme()
	return e("Frame", {
		Size = UDim2.fromOffset(BOX.X, BOX.Y),
		BackgroundTransparency = 1,
		LayoutOrder = props.layoutOrder,
	}, {
		Stroke = e("UIStroke", { Color = FAINT, Thickness = 1 }),
		Mark = e("TextLabel", {
			Size = UDim2.fromOffset(48, 48),
			Position = UDim2.fromScale(0.5, 0.42),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Text = "?",
			FontFace = theme.face.display,
			TextSize = 28,
			TextColor3 = FAINT,
		}),
		Name = e("TextLabel", {
			Size = UDim2.fromOffset(170, 28),
			Position = UDim2.new(0, 18, 1, -28),
			AnchorPoint = Vector2.new(0, 1),
			BackgroundTransparency = 1,
			Text = "UNFELT",
			FontFace = theme.face.display,
			TextSize = 21,
			TextColor3 = Color3.fromRGB(93, 99, 111),
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
	})
end

local function Label(props: { text: string, position: UDim2, color: Color3?, size: number? })
	local theme = ThemeContext.useTheme()
	return e("TextLabel", {
		Size = UDim2.fromOffset(400, 26),
		Position = props.position,
		BackgroundTransparency = 1,
		Text = props.text,
		FontFace = theme.face.bodyBold,
		TextSize = props.size or 20,
		TextColor3 = props.color or DIM,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
end

export type Props = {
	shrine: boolean,
	context: string,
	-- The mastery just attuned, to burst on its box.
	celebrate: { track: string, id: number }?,
	onCelebrated: () -> (),
	onChoose: (trackId: string) -> (),
}

local function Menu(props: Props)
	local theme = ThemeContext.useTheme()
	local attuned = ProgressionClient.attunement()
	local slots = ProgressionClient.attunementSlots()
	local passiveSlots = ProgressionClient.passiveSlots()
	local chosen = #ProgressionClient.chosenPassives()

	local function row(family: MasteryTracks.TrackFamily)
		local children: { [string]: any } = {
			Layout = e("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, GAP),
			}),
		}
		local count = 0
		for _, track in ipairs(MasteryTracks.list()) do
			if track.family == family then
				count += 1
				children[track.id] = e(Box, {
					track = track,
					attuned = table.find(attuned, track.id) ~= nil,
					shrine = props.shrine,
					context = props.context,
					layoutOrder = count,
					celebrate = if props.celebrate and props.celebrate.track == track.id
						then props.celebrate.id
						else nil,
					onCelebrated = props.onCelebrated,
					onActivated = function()
						props.onChoose(track.id)
					end,
				})
			end
		end
		if family == "element" then
			for index = 1, UNFELT do
				children[`Unfelt{index}`] = e(UnfeltBox, { layoutOrder = count + index })
			end
		end
		return e("Frame", {
			Size = UDim2.fromOffset(WIDTH, BOX.Y),
			BackgroundTransparency = 1,
		}, children)
	end

	local pips: { [string]: any } = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 8),
		}),
	}
	for index = 1, math.max(slots, 1) do
		pips[`Pip{index}`] = if index <= slots
			then e(Pip, { filled = index <= #attuned, layoutOrder = index })
			else nil
	end

	local top = 0
	local function at(height: number, gap: number?): UDim2
		local position = UDim2.fromOffset(0, top)
		top += height + (gap or 0)
		return position
	end

	local titlePosition = at(32, 36)
	local attackLabel = at(26, 12)
	local attackRow = at(BOX.Y, 36)
	local elementLabel = at(26, 12)
	local elementRow = at(BOX.Y, 0)

	return e("Frame", {
		Size = UDim2.fromOffset(WIDTH, top),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
	}, {
		-- Shrinks to fit a small screen; never grows past its design size.
		Fit = e("UIScale", { Scale = fitScale(Vector2.new(WIDTH, top)) }),
		Title = e("TextLabel", {
			Size = UDim2.fromOffset(500, 32),
			Position = titlePosition,
			BackgroundTransparency = 1,
			Text = if props.shrine then "MASTERIES  ·  SHRINE" else "MASTERIES",
			FontFace = theme.face.display,
			TextSize = 27,
			TextColor3 = INK,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		Slots = e("Frame", {
			Size = UDim2.fromOffset(520, 32),
			Position = UDim2.new(1, 0, 0, titlePosition.Y.Offset),
			AnchorPoint = Vector2.new(1, 0),
			BackgroundTransparency = 1,
		}, {
			Layout = e("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Right,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, 10),
			}),
			AttunedLabel = e("TextLabel", {
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, 32),
				BackgroundTransparency = 1,
				Text = if slots == 0 then "ATTUNED  —" else "ATTUNED",
				FontFace = theme.face.bodyBold,
				TextSize = 20,
				TextColor3 = INK,
				TextTransparency = 0.1,
				LayoutOrder = 1,
			}),
			Pips = if slots > 0
				then e("Frame", {
					AutomaticSize = Enum.AutomaticSize.X,
					Size = UDim2.fromOffset(0, 32),
					BackgroundTransparency = 1,
					LayoutOrder = 2,
				}, pips)
				else nil,
			Passives = e("TextLabel", {
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, 32),
				BackgroundTransparency = 1,
				Text = `      PASSIVES  {math.min(chosen, passiveSlots)} / {passiveSlots}`,
				FontFace = theme.face.bodyBold,
				TextSize = 20,
				TextColor3 = INK,
				TextTransparency = 0.1,
				LayoutOrder = 3,
			}),
		}),
		AttackLabel = e(Label, { text = "FIGHTING STYLE", position = attackLabel }),
		AttackRow = e("Frame", {
			Size = UDim2.fromOffset(WIDTH, BOX.Y),
			Position = attackRow,
			BackgroundTransparency = 1,
		}, { Row = row("attack") }),
		ElementLabel = e(Label, { text = "ELEMENTS", position = elementLabel }),
		ElementRow = e("Frame", {
			Size = UDim2.fromOffset(WIDTH, BOX.Y),
			Position = elementRow,
			BackgroundTransparency = 1,
		}, { Row = row("element") }),
	})
end

return Menu
