--!strict
-- The selected drop's details while loot is focused: the same card the inventory inspects with, so an
-- item reads the same on the ground as in the bag, standing beside the drop's label.
--
-- Read-only: a drop is taken by clicking its label, not from here. It switches on when focus opens and
-- swaps its content as the selection moves.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

local SwitchOn = require(script.Parent.Parent.Parent.components.SwitchOn)
local ItemCard = require(script.Parent.Parent.ItemInspectPanel.ItemCard)
local LootClient = require(script.Parent.Parent.Parent.controllers.LootClient)

local e = React.createElement

export type Props = {
	entry: LootClient.LootEntry,
	-- Top-left corner in screen pixels; a binding.
	position: any,
}

local LootDetails = {}

-- Pixels.
LootDetails.SIZE = Vector2.new(300, 430)

function LootDetails.render(props: Props)
	local entry = props.entry
	local meta = entry.meta or { rarity = entry.rarity, displayName = entry.displayName }

	return e("Frame", {
		Size = UDim2.fromOffset(LootDetails.SIZE.X, LootDetails.SIZE.Y),
		Position = props.position,
		-- Hidden until the container has placed it once, rather than flashing in the corner.
		Visible = props.position:map(function(position: UDim2)
			return position ~= UDim2.new()
		end),
		BackgroundTransparency = 1,
	}, {
		Surface = e(SwitchOn, {
			visible = true,
			size = LootDetails.SIZE,
		}, {
			Card = e(ItemCard, {
				item = {
					uid = entry.uid,
					itemId = entry.itemId,
					stackSize = entry.stackSize or 1,
					meta = meta :: any,
				},
				readOnly = true,
			}),
		}),
	})
end

return LootDetails
