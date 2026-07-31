--!strict
-- The paper-doll: ten sockets arranged around a body silhouette, plus a strip of every equippable
-- item in the inventory below it.
--
-- Ported from docs/ui/EquipmentPanel.rbxmx, whose container structure is reproduced rather than
-- flattened. The Studio tree nests the sockets in columns:
--
--   EquipmentContent          Left (Primary) | Middle | Right (Secondary)
--     Middle > ArmorContainer   Left (Ring1, Hands) | Middle (Head, Body, Belt) | Right (Neck, Ring2, Feet)
--
-- The nesting is not incidental. Sizing every socket against its own column, and locking the small
-- ones square with an aspect constraint, is what keeps the arrangement consistent -- placing ten
-- sockets absolutely means ten independently tuned rectangles, which drift out of proportion the
-- moment any of them is adjusted.
--
-- One container in the export, ConsumableBar, is empty in every sense: no bound slot, no attribute,
-- no runtime reference anywhere in the client. It is dropped rather than ported as a placeholder
-- (Guardrail 1 covers *capabilities*, and this one never had any).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

local PanelShell = require(script.Parent.Parent.Parent.components.PanelShell)
local Header = require(script.Parent.Parent.Parent.components.Header)
local Slot = require(script.Parent.Parent.Parent.components.Slot)
local Grid = require(script.Parent.Parent.Parent.components.Grid)

local ThemeContext = require(script.Parent.Parent.Parent.hooks.ThemeContext)

local Selector = require(script.Parent.Parent.Parent.selectors.equipment)

local e = React.createElement

export type Props = {
	view: Selector.EquipmentView,
	selectedSlot: Selector.EquipSlot?,
	onSlotActivated: (slot: Selector.EquipSlot, uid: string?) -> (),
	onCandidateActivated: (candidate: Selector.CandidateView) -> (),
}

-- Column widths. `LOCAL` is what each column is given inside its parent; `ABS` is the same column as
-- a fraction of the whole doll. Both are derived from one set of numbers so they cannot disagree.
local ARMOR_WIDTH = 0.5
local COLUMN_LOCAL = { weapon = 0.25, inner = 0.26, centre = 0.44, outer = 0.26 }
local COLUMN_ABS = {
	weapon = COLUMN_LOCAL.weapon,
	inner = ARMOR_WIDTH * COLUMN_LOCAL.inner,
	centre = ARMOR_WIDTH * COLUMN_LOCAL.centre,
	outer = ARMOR_WIDTH * COLUMN_LOCAL.outer,
}

-- Shared vertical anchors, as fractions of the doll's height. Sockets that must line up across
-- columns reference the same constant, so they align by construction rather than by two numbers
-- that happen to agree -- stacking each column with a list layout cannot do this, because the inner
-- columns hold different numbers of sockets and centring them puts the rings at different heights.
local ROW = {
	head = 0.00,
	weapon = 0.18,
	neck = 0.21,
	body = 0.26,
	ring = 0.434,
	extremity = 0.73,
	waist = 0.795,
}

-- Shared widths, for the same reason. Head, Hands and Feet are one size; Neck and the rings another.
local SQUARE = 0.101
local SMALL = 0.081

type SocketShape = {
	column: string,
	-- Width as a fraction of the whole doll, converted into column-local space at render. Declaring
	-- these in doll space is what lets sockets in columns of different widths be genuinely equal --
	-- in column-local space the same visual size needs different numbers.
	width: number,
	-- Height, as a fraction of the doll. Square sockets omit it and derive it from the width.
	height: number?,
	square: boolean?,
	y: number,
	-- Silhouette hinting what belongs in the socket. Empty renders nothing, which is right for the
	-- weapon sockets: they take too many shapes for one glyph to represent honestly.
	placeholderIcon: string,
}

local SOCKET_SHAPE: { [string]: SocketShape } = {
	-- Mirrored pairs share a shape and a row, so they cannot drift apart.
	Main = { column = "weapon", width = 0.175, height = 0.55, y = ROW.weapon, placeholderIcon = "" },
	Secondary = { column = "weapon", width = 0.175, height = 0.55, y = ROW.weapon, placeholderIcon = "" },

	Head = { column = "centre", width = SQUARE, square = true, y = ROW.head, placeholderIcon = "" },
	Body = { column = "centre", width = 0.176, height = 0.52, y = ROW.body, placeholderIcon = "" },
	Waist = { column = "centre", width = 0.172, height = 0.13, y = ROW.waist, placeholderIcon = "" },

	Ring1 = { column = "inner", width = SMALL, square = true, y = ROW.ring, placeholderIcon = "" },
	Hands = { column = "inner", width = SQUARE, square = true, y = ROW.extremity, placeholderIcon = "" },

	Neck = { column = "outer", width = SMALL, square = true, y = ROW.neck, placeholderIcon = "" },
	Ring2 = { column = "outer", width = SMALL, square = true, y = ROW.ring, placeholderIcon = "" },
	Feet = { column = "outer", width = SQUARE, square = true, y = ROW.extremity, placeholderIcon = "" },
}

-- A column in the doll. Children are centred horizontally within it and hung from their own row.
local function Column(props: { width: number, layoutOrder: number, children: any })
	return e("Frame", {
		Size = UDim2.fromScale(props.width, 1),
		LayoutOrder = props.layoutOrder,
		BackgroundTransparency = 1,
	}, props.children)
end

local function EquipmentView(props: Props)
	local theme = ThemeContext.useTheme()

	local bySlot: { [string]: Selector.SlotView } = {}
	for _, slotView in ipairs(props.view.slots) do
		bySlot[slotView.slot] = slotView
	end

	local function socket(slot: string): any
		local slotView = bySlot[slot]
		local shape = SOCKET_SHAPE[slot]
		if not slotView or not shape then
			return nil
		end
		return e(Slot, {
			variant = "socket",
			icon = slotView.icon,
			tint = slotView.tint,
			count = slotView.count,
			selected = props.selectedSlot == slotView.slot,
			placeholderIcon = shape.placeholderIcon,
			-- Doll-space width converted into the column's own space. A square socket's height is
			-- derived by the aspect constraint, so the 1 here is a placeholder it overrides.
			size = UDim2.fromScale(shape.width / COLUMN_ABS[shape.column], shape.height or 1),
			aspectRatio = if shape.square then 1 else nil,
			position = UDim2.fromScale(0.5, shape.y),
			anchorPoint = Vector2.new(0.5, 0),
			onActivated = function()
				props.onSlotActivated(slotView.slot, slotView.uid)
			end,
		})
	end

	local candidates: { [string]: any } = {}
	for index, candidate in ipairs(props.view.candidates) do
		candidates[candidate.key] = e(Slot, {
			icon = candidate.icon,
			tint = candidate.tint,
			count = candidate.count,
			layoutOrder = index,
			onActivated = function()
				props.onCandidateActivated(candidate)
			end,
		})
	end


	return e(PanelShell, { layout = "free", padding = theme.metrics.paddingLg }, {
		Title = e(Header, {
			title = "EQUIPMENT",
			width = 0.30,
			height = 0.08,
			position = UDim2.fromScale(0.5, 0.05),
			anchorPoint = Vector2.new(0.5, 0),
		}),

		Paperdoll = e("Frame", {
			Size = UDim2.fromScale(0.94, 0.42),
			Position = UDim2.fromScale(0.5, 0.18),
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundTransparency = 1,
		}, {
			Layout = e("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),

			Left = e(Column, {
				width = COLUMN_LOCAL.weapon,
				layoutOrder = 1,
				children = { Main = socket("Main") },
			}),

			Armor = e("Frame", {
				Size = UDim2.fromScale(ARMOR_WIDTH, 1),
				LayoutOrder = 2,
				BackgroundTransparency = 1,
			}, {
				Layout = e("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
				Inner = e(Column, {
					width = COLUMN_LOCAL.inner,
					layoutOrder = 1,
					children = { Ring1 = socket("Ring1"), Hands = socket("Hands") },
				}),
				Centre = e(Column, {
					width = COLUMN_LOCAL.centre,
					layoutOrder = 2,
					children = { Head = socket("Head"), Body = socket("Body"), Waist = socket("Waist") },
				}),
				Outer = e(Column, {
					width = COLUMN_LOCAL.outer,
					layoutOrder = 3,
					children = { Neck = socket("Neck"), Ring2 = socket("Ring2"), Feet = socket("Feet") },
				}),
			}),

			Right = e(Column, {
				width = COLUMN_LOCAL.weapon,
				layoutOrder = 3,
				children = { Secondary = socket("Secondary") },
			}),
		}),

		Candidates = e(Grid, {
			size = UDim2.fromScale(0.92, 0.32),
			position = UDim2.fromScale(0.5, 0.655),
			anchorPoint = Vector2.new(0.5, 0),
			cell = 130,
			gap = theme.metrics.paddingMd,
			padding = theme.metrics.paddingMd,
			stroke = true,
		}, candidates),
	})
end

return EquipmentView
