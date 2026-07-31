--!strict
-- Derives the skill bar's display shape from a profile's filled slots: which icon to show and which
-- key activates it.
--
-- Pure: the keybind label is derived from ActionConfig rather than duplicated as a lookup table, so
-- rebinding "Skill3" to a different key updates the bar without touching this file. Only slots 1-5
-- have a bound key today (Inputs.init only wires that range), so a slot outside it renders with no
-- keybind label rather than a guess.
--
-- Slot 1 has both a key ("One") and a mouse binding (MouseButton1); mouse wins when both exist, which
-- is what the fist-icon screenshots ("M1") are showing. The old runtime's KeyLabel never reflected
-- this at all -- it cloned a single Studio template whose text was hardcoded to "M1" for every slot,
-- so slots 2 and 3 showed the wrong key in practice. This selector computes the real bound key per
-- slot instead.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientSpec = require(ReplicatedStorage.Shared.skills.ClientSpec)
local ActionConfig = require(script.Parent.Parent.Parent.input.ActionConfig)
local SkillSlots = require(script.Parent.Parent.Parent.SkillsFramework.SkillSlots)

local Selector = {}

export type SlotView = {
	index: number,
	skill: string,
	icon: string,
	keyLabel: string?,
}

-- Roblox spells digit keys out ("One", "Two", ...); the bar wants the digit itself.
local NUMBER_KEY_LABELS: { [string]: string } = {
	Zero = "0",
	One = "1",
	Two = "2",
	Three = "3",
	Four = "4",
	Five = "5",
	Six = "6",
	Seven = "7",
	Eight = "8",
	Nine = "9",
}

local function formatBinding(binding: ActionConfig.Binding): string?
	if binding.mouse == Enum.UserInputType.MouseButton1 then
		return "M1"
	end
	if binding.mouse == Enum.UserInputType.MouseButton2 then
		return "M2"
	end
	if binding.key then
		local name = binding.key.Name
		return NUMBER_KEY_LABELS[name] or name
	end
	return nil
end

local function keyLabelFor(slotIndex: number): string?
	local core = ActionConfig.contexts.Core
	local action = core and core.actions["Skill" .. tostring(slotIndex)]
	if not action then
		return nil
	end

	-- Two passes rather than one: a mouse binding should win over a keyboard one when a slot has
	-- both (slot 1 does), so the label always reads "M1" rather than whichever binding happened to
	-- be declared first in ActionConfig.
	local keyLabel: string? = nil
	for _, binding in ipairs(action.bindings) do
		if binding.type == "press" then
			if binding.mouse then
				local label = formatBinding(binding)
				if label then
					return label
				end
			elseif not keyLabel then
				keyLabel = formatBinding(binding)
			end
		end
	end
	return keyLabel
end

function Selector.buildSlots(filled: { SkillSlots.FilledSlot }): { SlotView }
	local views: { SlotView } = {}
	for _, slot in ipairs(filled) do
		local spec = ClientSpec[slot.skill]
		local icon = if spec and type(spec) == "table" and type(spec.icon) == "string" then spec.icon else ""
		table.insert(views, {
			index = slot.index,
			skill = slot.skill,
			icon = icon,
			keyLabel = keyLabelFor(slot.index),
		})
	end
	return views
end

-- Ported from SkillSlotUI.formatTime verbatim -- same three bands (minutes, whole seconds, one
-- decimal under 10s) so the last-second countdown reads the same as it always has.
function Selector.formatTime(remaining: number): string
	if remaining <= 0 then
		return ""
	end
	if remaining >= 60 then
		local m = math.floor(remaining / 60)
		local s = math.floor(remaining % 60)
		return string.format("%d:%02d", m, s)
	elseif remaining >= 10 then
		return tostring(math.floor(remaining + 0.5))
	else
		return string.format("%.1f", remaining)
	end
end

return Selector
