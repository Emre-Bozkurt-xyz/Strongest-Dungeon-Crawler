--!strict
-- Studio-only switches for dev views, with a change signal so React can subscribe.
--
-- F7 toggles the style tile. The listener lives here rather than in a component so the key works
-- whether or not the surface showing the tile is currently mounted.

local UserInputService = game:GetService("UserInputService")

local DevFlags = {}

export type Flag = "styleTile"

local values: { [Flag]: boolean } = { styleTile = false }
local listeners: { [{}]: () -> () } = {}

function DevFlags.get(flag: Flag): boolean
	return values[flag]
end

function DevFlags.set(flag: Flag, value: boolean)
	if values[flag] == value then
		return
	end
	values[flag] = value
	for _, listener in pairs(listeners) do
		task.spawn(listener)
	end
end

function DevFlags.onChanged(callback: () -> ()): () -> ()
	local token = {}
	listeners[token] = callback
	return function()
		listeners[token] = nil
	end
end

-- Roblox marks F7 as already processed (a core binding claims it), so `gameProcessed` cannot be the
-- guard here; only typing into a text box is excluded.
UserInputService.InputBegan:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.F7 and not UserInputService:GetFocusedTextBox() then
		DevFlags.set("styleTile", not values.styleTile)
	end
end)

return DevFlags
