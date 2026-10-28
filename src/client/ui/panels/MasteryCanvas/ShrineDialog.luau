--!strict
-- The shrine's confirmation, over the mastery menu (docs/planning/mastery-mind-space.md, "The
-- attunement shrine").
--
-- A free slot asks once and attunes. With every slot held it becomes a swap: the player picks which
-- attunement to release and confirms both together, with the cost shown, so a slot is never left
-- empty halfway through. An attuned mastery is only loosened by attuning something in its place.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local MasteryTracks = require(ReplicatedStorage.Shared.progression.MasteryTracks)
local Attunement = require(ReplicatedStorage.Shared.progression.Attunement)

local ThemeContext = require(script.Parent.Parent.Parent.hooks.ThemeContext)
local Brackets = require(script.Parent.Parent.Parent.components.Brackets)
local useSpring = require(script.Parent.Parent.Parent.hooks.useSpring)
local UISound = require(script.Parent.Parent.Parent.UISound)
local ProgressionClient = require(script.Parent.Parent.Parent.Parent.Progression.ProgressionClient)

local e = React.createElement

local WIDTH = 540
local PADDING = 32
local INK = Color3.fromRGB(238, 241, 246)

-- The mind-space's own button: white on black, filled white when it is the choice that will be
-- made. The System's buttons carry its accent colour, which this space does without.
local function MonoButton(props: {
	text: string,
	filled: boolean?,
	enabled: boolean?,
	size: UDim2,
	layoutOrder: number,
	onActivated: () -> (),
})
	local theme = ThemeContext.useTheme()
	local hovered, setHovered = React.useState(false)
	local enabled = props.enabled ~= false
	local hover = useSpring(if hovered and enabled then 1 else 0, theme.motion.snap)
	local filled = props.filled == true and enabled
	return e("TextButton", {
		Size = props.size,
		BackgroundColor3 = INK,
		BackgroundTransparency = if filled
			then 0
			else hover:map(function(h: number)
				return 1 - 0.08 * h
			end),
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Text = props.text,
		FontFace = theme.face.bodyBold,
		TextSize = 17,
		TextColor3 = if filled then Color3.fromRGB(4, 5, 8) else INK,
		TextTransparency = if enabled then 0 else 0.6,
		LayoutOrder = props.layoutOrder,
		[React.Event.MouseEnter] = function()
			setHovered(true)
			if enabled then
				UISound.play("hover")
			end
		end,
		[React.Event.MouseLeave] = function()
			setHovered(false)
		end,
		[React.Event.Activated] = function()
			if enabled then
				props.onActivated()
			end
		end,
	}, {
		Stroke = e("UIStroke", {
			Color = INK,
			Thickness = 1,
			Transparency = if enabled then 0.45 else 0.8,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
	})
end

export type Props = {
	trackId: string,
	onClose: () -> (),
	-- After a change is sent: the menu plays its burst on the attuned box.
	onAttuned: (trackId: string) -> (),
}

local function ShrineDialog(props: Props)
	local theme = ThemeContext.useTheme()
	local release, setRelease = React.useState(nil :: string?)
	-- Measured from the content: an automatically sized panel would also grow to fit the corner
	-- brackets, which size themselves to the panel.
	local height, setHeight = React.useState(0)
	local track = MasteryTracks.get(props.trackId)
	if not track then
		return nil
	end
	local name = string.upper(track.displayName)
	local attuned = ProgressionClient.attunement()
	local slots = ProgressionClient.attunementSlots()
	local isAttuned = table.find(attuned, track.id) ~= nil

	local title: string
	local lines: { string } = {}
	local cost: string? = nil
	local confirm: string? = nil
	local canConfirm = true
	local choices: { string } = {}

	if isAttuned then
		title = `{name} IS ATTUNED`
		table.insert(lines, "To loosen it, attune something else in its place.")
	elseif slots == 0 then
		title = "NOT YET"
		local level = Attunement.nextSlotLevel(ProgressionClient.characterProgress().level)
		table.insert(lines, if level then `Your mind can hold an attunement at level {level}.` else "No slot is open.")
	elseif #attuned < slots then
		title = `ATTUNE {name}?`
		table.insert(lines, `Your mind will hold to {string.lower(track.displayName)} as one of its {slots} anchors.`)
		table.insert(
			lines,
			if track.family == "attack"
				then "Its earned forms and passives wake."
				else "Its tree grows half again as strong, and its last node opens."
		)
		cost = "FREE  ·  A SLOT IS OPEN"
		confirm = "ATTUNE"
	else
		title = "SWAP AN ATTUNEMENT"
		table.insert(
			lines,
			`Every anchor is held. Choose one to release for {string.lower(track.displayName)}. Nothing you have learned is lost.`
		)
		choices = attuned
		cost = Attunement.SWAP_COST
		confirm = "SWAP"
		canConfirm = release ~= nil
	end

	local children: { [string]: any } = {
		Layout = e("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 14),
		}),
		Padding = e("UIPadding", {
			PaddingLeft = UDim.new(0, PADDING),
			PaddingRight = UDim.new(0, PADDING),
			PaddingTop = UDim.new(0, PADDING),
			PaddingBottom = UDim.new(0, PADDING),
		}),
		Title = e("TextLabel", {
			Size = UDim2.new(1, 0, 0, 28),
			BackgroundTransparency = 1,
			Text = title,
			FontFace = theme.face.display,
			TextSize = 21,
			TextColor3 = INK,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = 1,
		}),
	}
	for index, line in ipairs(lines) do
		children[`Line{index}`] = e("TextLabel", {
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.fromScale(1, 0),
			BackgroundTransparency = 1,
			Text = line,
			FontFace = theme.face.body,
			TextSize = 19,
			TextColor3 = INK,
			TextTransparency = if index == 1 then 0.1 else 0.3,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = 1 + index,
		})
	end
	if #choices > 0 then
		local row: { [string]: any } = {
			Layout = e("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, 10),
			}),
		}
		for index, trackId in ipairs(choices) do
			local entry = MasteryTracks.get(trackId)
			row[trackId] = e(MonoButton, {
				text = `RELEASE {string.upper(if entry then entry.displayName else trackId)}`,
				filled = release == trackId,
				size = UDim2.new(1 / #choices, -10 * (#choices - 1) / #choices, 1, 0),
				layoutOrder = index,
				onActivated = function()
					setRelease(trackId)
				end,
			})
		end
		children.Choices = e("Frame", {
			Size = UDim2.new(1, 0, 0, 42),
			BackgroundTransparency = 1,
			LayoutOrder = 10,
		}, row)
	end
	if cost then
		children.Cost = e("Frame", {
			Size = UDim2.new(1, 0, 0, 30),
			BackgroundTransparency = 1,
			LayoutOrder = 11,
		}, {
			Rule = e("Frame", {
				Size = UDim2.new(1, 0, 0, 1),
				BackgroundColor3 = INK,
				BackgroundTransparency = 0.86,
				BorderSizePixel = 0,
			}),
			Label = e("TextLabel", {
				Size = UDim2.new(0.3, 0, 1, 0),
				BackgroundTransparency = 1,
				Text = "COST",
				FontFace = theme.face.bodyBold,
				TextSize = 17,
				TextColor3 = INK,
				TextTransparency = 0.4,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			Value = e("TextLabel", {
				Size = UDim2.new(0.7, 0, 1, 0),
				Position = UDim2.fromScale(1, 0),
				AnchorPoint = Vector2.new(1, 0),
				BackgroundTransparency = 1,
				Text = cost,
				FontFace = theme.face.mono,
				TextSize = 17,
				TextColor3 = INK,
				TextTransparency = 0.15,
				TextXAlignment = Enum.TextXAlignment.Right,
			}),
		})
	end
	children.Buttons = e("Frame", {
		Size = UDim2.new(1, 0, 0, 42),
		BackgroundTransparency = 1,
		LayoutOrder = 12,
	}, {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 10),
		}),
		Close = e(MonoButton, {
			text = if confirm then "CANCEL" else "CLOSE",
			size = UDim2.new(0, 140, 1, 0),
			layoutOrder = 1,
			onActivated = props.onClose,
		}),
		Confirm = if confirm
			then e(MonoButton, {
				text = confirm,
				filled = true,
				enabled = canConfirm,
				size = UDim2.new(0, 160, 1, 0),
				layoutOrder = 2,
				onActivated = function()
					UISound.play("attune")
					if release then
						ProgressionClient.swapAttuned(release, track.id)
					else
						ProgressionClient.setAttuned(track.id, true)
					end
					props.onAttuned(track.id)
					props.onClose()
				end,
			})
			else nil,
	})

	-- The scrim takes any press outside the panel and closes it.
	return e("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		AutoButtonColor = false,
		Text = "",
		ZIndex = 50,
		[React.Event.Activated] = props.onClose,
	}, {
		Panel = e("TextButton", {
			Size = UDim2.fromOffset(WIDTH, height),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Color3.fromRGB(8, 9, 13),
			BackgroundTransparency = 0.04,
			AutoButtonColor = false,
			Text = "",
			BorderSizePixel = 0,
		}, {
			Stroke = e("UIStroke", { Color = INK, Thickness = 1, Transparency = 0.82 }),
			Corners = e(Brackets, { size = "small", color = INK, edgeTransparency = 1 }),
			Content = e("Frame", {
				AutomaticSize = Enum.AutomaticSize.Y,
				Size = UDim2.fromScale(1, 0),
				BackgroundTransparency = 1,
				[React.Change.AbsoluteSize] = function(rbx: Frame)
					setHeight(rbx.AbsoluteSize.Y)
				end,
			}, children),
		}),
	})
end

return ShrineDialog
