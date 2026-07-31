--!strict
-- Presentational skill hotbar: a horizontal row of slots anchored to the bottom-centre of the
-- screen. Anchor, position, size and the list layout are taken directly from the SkillSlots frame in
-- docs/ui/HUD.rbxmx, the only place the bar's screen placement was authored.
--
-- `AutomaticSize.X` means the authored Size.X (290px) is only the initial width; the bar grows and
-- shrinks with however many slots the active profile actually fills.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local Selector = require(script.Parent.Parent.Parent.selectors.skillSlots)
local SkillSlotButton = require(script.Parent.SkillSlotButton)

local e = React.createElement

export type Props = {
	slots: { Selector.SlotView },
	gcdProgress: any,
	castBlocked: any,
	-- The skill currently executing, if any. Resolved once for the bar rather than per slot: only one
	-- session can be live at a time, so a hook per slot would be the same query repeated.
	activeSkill: string?,
}

local function SkillBar(props: Props)
	-- Keyed by slot index (Guardrail 5) rather than array position, so a slot keeps its identity --
	-- and its cooldown binding -- across a reorder or a profile swap that drops a middle slot.
	local children: { [string]: any } = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Left,
			VerticalAlignment = Enum.VerticalAlignment.Top,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 10),
		}),
	}

	for order, slot in ipairs(props.slots) do
		children[tostring(slot.index)] = e(SkillSlotButton, {
			index = slot.index,
			skill = slot.skill,
			icon = slot.icon,
			keyLabel = slot.keyLabel,
			layoutOrder = order,
			gcdProgress = props.gcdProgress,
			castBlocked = props.castBlocked,
			active = props.activeSkill == slot.skill,
		})
	end

	return e("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0.99, 0),
		Size = UDim2.new(0, 290, 0, 75),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
	}, children)
end

return SkillBar
