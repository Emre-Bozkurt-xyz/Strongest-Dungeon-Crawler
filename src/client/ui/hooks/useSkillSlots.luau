--!strict
-- The active profile's filled skill slots, read from SkillSlots.
--
-- Unlike the BindableEvent-backed stores, SkillSlots' change signals are a plain in-process callback
-- list (`fire` just calls each subscriber with `task.spawn`), and they only ever pass a profileId --
-- never the slot data itself -- so there is no payload to distrust here. The store is always re-read
-- directly regardless.
--
-- No useReducer counter either (contrast useStats): getFilledSlots() builds a fresh array on every
-- call, so its identity changes on every read and useState re-renders normally. The counter is only
-- needed when a re-read comes back with a stable identity.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local SkillSlots = require(script.Parent.Parent.Parent.SkillsFramework.SkillSlots)

local function read(): { SkillSlots.FilledSlot }
	return SkillSlots.getFilledSlots()
end

local function useSkillSlots(): { SkillSlots.FilledSlot }
	local slots, setSlots = React.useState(read)

	React.useEffect(function()
		local offSlots = SkillSlots.onSlotsChanged(function()
			setSlots(read())
		end)
		local offProfile = SkillSlots.onProfileChanged(function()
			setSlots(read())
		end)
		-- A change may have landed between the initial useState(read) and this effect running.
		setSlots(read())
		return function()
			offSlots()
			offProfile()
		end
	end, {})

	return slots
end

return useSkillSlots
