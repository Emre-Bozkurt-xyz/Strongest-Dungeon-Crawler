--!strict
-- Returns `value` while `visible`, and the last value seen while visible once it is not.
--
-- A panel fading out keeps rendering until the fade completes (PanelHost.present). Its live data has
-- usually already gone by then -- the loot was picked up, the inspected item was deselected -- so
-- rendering it would fade out an empty panel. Holding the last shown value keeps the exit looking
-- like the thing that was there.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

local function useHeldWhileHidden<T>(value: T, visible: boolean?): T
	local held = React.useRef(value)
	if visible ~= false then
		held.current = value
	end
	return held.current :: T
end

return useHeldWhileHidden
