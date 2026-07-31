--!strict
-- Player HP/MP/Stamina and derived combat stats, read from StatsClient.
--
-- Bootstrap already triggers the first fetch (StatsClient.requestStatsUpdate), so unlike
-- useAttributes this hook must not request on its own -- a hook mounting before that request
-- resolves would race it for no benefit. It only reads the current snapshot and subscribes.
--
-- The payload from `onChanged` is deliberately ignored. StatsClient publishes through a
-- BindableEvent, and BindableEvents deep-copy their arguments across the Fire/Event boundary,
-- stripping metatables and functions. PlayerStats is a table of pool *objects* with
-- getCurrentValue/getValue methods, so what arrives on the far side is a lifeless copy whose methods
-- are gone -- consumers guarding on `type(pool.getValue) == "function"` then silently read nothing.
-- The signal is treated as a bare notification and the live object is re-read from the module.
--
-- Re-reading also means the value has a stable identity, so setting it as state would bail out of
-- re-rendering. A counter forces the render instead; this is what useSyncExternalStore would do, and
-- react-lua 17 does not have it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local StatsClient = require(script.Parent.Parent.Parent.StatsClient)
local StatTypes = require(ReplicatedStorage.Shared.StatTypes)

local function useStats(): StatTypes.PlayerStats?
	local _, bump = React.useReducer(function(count: number): number
		return count + 1
	end, 0)

	React.useEffect(function()
		return StatsClient.onChanged(function()
			bump(nil)
		end)
	end, {})

	return StatsClient.getCurrentStats()
end

return useStats
