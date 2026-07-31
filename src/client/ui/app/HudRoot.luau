--!strict
-- Renders every registered screen-space element into the persistent ScreenRoot.
--
-- Each entry gets a full-screen transparent frame of its own so siblings cannot fight over layout,
-- and so one element's failure is contained to its own subtree.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ScreenRegistry = require(script.Parent.ScreenRegistry)

local e = React.createElement

local function HudRoot()
	local children: { [string]: any } = {}

	for index, entry in ipairs(ScreenRegistry.list()) do
		children[entry.id] = e("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = entry.zIndex or index,
		}, {
			Content = e(entry.component),
		})
	end

	return e(React.Fragment, nil, children)
end

return HudRoot
