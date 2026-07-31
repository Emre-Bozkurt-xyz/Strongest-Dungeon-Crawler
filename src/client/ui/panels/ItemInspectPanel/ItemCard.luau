--!strict
-- Renders one item's details: icon well, title bar, scrolling info, action bar.
--
-- Presentational and driven entirely by `uid`, so it has no opinion about *why* an item is being
-- shown. That is what makes it reusable as the R14 hover tooltip, which inspects an arbitrary item
-- rather than the menu's inspect state. The container that knows about menu state is init.luau.
--
-- The four-block layout, the layered translucent surfaces and the heavy half-transparent outlines
-- come from the Studio panel (docs/ui/ItemInspectPanel.rbxmx). What changed is the info block: the
-- old panel emitted one flat list of pre-formatted RichText lines, so requirements, weapon stats and
-- affixes were twenty identical rows. They are grouped and label/value aligned here, and an unmet
-- requirement is coloured rather than silent.
--
-- Interaction is unchanged from the old panel -- buttons, not hover or carry (R15).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

local Panel = require(script.Parent.Parent.Parent.components.Panel)
local PanelShell = require(script.Parent.Parent.Parent.components.PanelShell)
local Header = require(script.Parent.Parent.Parent.components.Header)
local Icon = require(script.Parent.Parent.Parent.components.Icon)
local Text = require(script.Parent.Parent.Parent.components.Text)
local Button = require(script.Parent.Parent.Parent.components.Button)
local ScrollList = require(script.Parent.Parent.Parent.components.ScrollList)

local ThemeContext = require(script.Parent.Parent.Parent.hooks.ThemeContext)
local useInventory = require(script.Parent.Parent.Parent.hooks.useInventory)
local useAttributes = require(script.Parent.Parent.Parent.hooks.useAttributes)

local ItemActions = require(script.Parent.Parent.Parent.actions.ItemActions)
local Selector = require(script.Parent.Parent.Parent.selectors.itemInspect)

local Registry = require(ReplicatedStorage.Shared.items.Registry)
local EquipmentDefUtils = require(ReplicatedStorage.Shared.items.EquipmentDefUtils)

local e = React.createElement

export type Props = {
	-- Which item to inspect. nil renders the empty state.
	uid: string?,
}

local RARITY_COLORS: { [string]: Color3 } = {
	normal = Color3.fromRGB(190, 190, 190),
	magic = Color3.fromRGB(120, 160, 255),
	rare = Color3.fromRGB(240, 210, 110),
	unique = Color3.fromRGB(230, 140, 70),
}

-- Canvas pixels. The surface is 1.875 studs wide at 300 px/stud, so a row of 17px rendered at
-- roughly 9 screen pixels at normal viewing distance -- unreadable. These are sized for legibility
-- at arm's length from the panel, not for fitting the most rows.
local ROW_HEIGHT = 42
local ROW_GAP = 4
local ROW_TEXT = 30
local HEADING_HEIGHT = 32
local HEADING_TEXT = 24
local LABEL_WIDTH = 0.58

-- A titled group. One real container rather than a Fragment, so the section has an Instance of its
-- own to lay out, and children merge in flat.
--
-- Height is computed rather than left to AutomaticSize. These sections sit inside a ScrollingFrame
-- with AutomaticCanvasSize that is itself sized by UIFlexItem, and an auto-sized child in that chain
-- makes the constraint circular -- Roblox resolves it inconsistently, which showed up as label and
-- value columns drifting further apart the further down the list they were.
local function Section(props: { title: string, layoutOrder: number, children: any })
	local children: { [string]: any } = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, ROW_GAP),
		}),
		Heading = e(Text, {
			text = string.upper(props.title),
			role = "MutedText",
			layoutOrder = 0,
			size = UDim2.new(1, 0, 0, HEADING_HEIGHT),
			textSize = HEADING_TEXT,
		}),
	}
	local rowCount = 0
	for key, child in pairs(props.children) do
		children[key] = child
		rowCount += 1
	end

	return e("Frame", {
		LayoutOrder = props.layoutOrder,
		Size = UDim2.new(1, 0, 0, HEADING_HEIGHT + rowCount * (ROW_HEIGHT + ROW_GAP)),
		BackgroundTransparency = 1,
	}, children)
end

-- A label/value row. `role` carries the semantics: an unmet requirement is RequirementUnmet, which
-- is where the theme's danger colour enters (Guardrail 3 -- no colour literals here).
local function Row(props: { label: string, value: string, role: any, layoutOrder: number })
	return e("Frame", {
		LayoutOrder = props.layoutOrder,
		Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
		BackgroundTransparency = 1,
	}, {
		Label = e(Text, {
			text = props.label,
			role = props.role,
			size = UDim2.new(LABEL_WIDTH, 0, 1, 0),
			textSize = ROW_TEXT,
		}),
		Value = e(Text, {
			text = props.value,
			role = props.role,
			size = UDim2.new(1 - LABEL_WIDTH, 0, 1, 0),
			position = UDim2.fromScale(LABEL_WIDTH, 0),
			alignX = Enum.TextXAlignment.Right,
			textSize = ROW_TEXT,
		}),
	})
end

local function ItemCard(props: Props)
	local theme = ThemeContext.useTheme()
	local inventory = useInventory()
	local attributes = useAttributes()

	local item = if props.uid then inventory.items[props.uid] else nil
	local view = Selector.buildView(item, attributes)

	if not view.found then
		return e(PanelShell, nil, {
			Empty = e(Text, {
				text = "No item selected",
				role = "MutedText",
				alignX = Enum.TextXAlignment.Center,
				size = UDim2.fromScale(1, 1),
				textSize = ROW_TEXT,
			}),
		})
	end

	local def = item and Registry.get(item.itemId)
	local location = if props.uid
		then Selector.getItemLocation(props.uid, inventory.inventory, inventory.equipment)
		else nil

	-- Sections are assembled with explicit layout orders so the ordering is visible in one place
	-- rather than implied by call sequence.
	local sections: { [string]: any } = {}
	local order = 0
	local function nextOrder(): number
		order += 10
		return order
	end

	do
		local rows: { [string]: any } = {
			Rarity = e(Row, { label = "Rarity", value = view.rarity, role = "BodyText", layoutOrder = 1 }),
		}
		if view.itemLevel then
			rows.ItemLevel = e(Row, {
				label = "Item Level",
				value = tostring(view.itemLevel),
				role = "BodyText",
				layoutOrder = 2,
			})
		end
		if view.weapon then
			rows.Class = e(Row, {
				label = "Type",
				value = `{view.weapon.class} ({view.weapon.handedness})`,
				role = "BodyText",
				layoutOrder = 3,
			})
		end
		sections.Overview = e(Section, { title = "Overview", layoutOrder = nextOrder(), children = rows })
	end

	if view.weapon then
		local weapon = view.weapon
		local rows: { [string]: any } = {}
		for index, damage in ipairs(weapon.damages) do
			rows[`Damage{index}`] = e(Row, {
				label = `{damage.damageType} Damage`,
				value = `{damage.min} - {damage.max}`,
				role = "BodyText",
				layoutOrder = index,
			})
		end
		rows.AttackSpeed = e(Row, {
			label = "Attack Speed",
			value = string.format("%.2f", weapon.attackSpeed),
			role = "BodyText",
			layoutOrder = 50,
		})
		if weapon.critChance then
			rows.Crit = e(Row, {
				label = "Critical Chance",
				value = `{math.floor(weapon.critChance * 100 + 0.5)}%`,
				role = "BodyText",
				layoutOrder = 51,
			})
		end
		if weapon.range then
			rows.Range = e(Row, {
				label = "Range",
				value = string.format("%.1f", weapon.range),
				role = "BodyText",
				layoutOrder = 52,
			})
		end
		sections.Weapon = e(Section, { title = "Weapon", layoutOrder = nextOrder(), children = rows })
	end

	if view.charges then
		local charges = view.charges
		sections.Charges = e(Section, {
			title = "Charges",
			layoutOrder = nextOrder(),
			children = {
				Row = e(Row, {
					label = "Remaining",
					value = if charges.max then `{charges.current} / {charges.max}` else tostring(charges.current),
					role = if charges.current <= 0 then "RequirementUnmet" else "BodyText",
					layoutOrder = 1,
				}),
			},
		})
	end

	if #view.affixes > 0 then
		local rows: { [string]: any } = {}
		for index, affix in ipairs(view.affixes) do
			rows[`Affix{index}`] = e(Row, {
				label = affix.label,
				value = affix.value,
				role = "BodyText",
				layoutOrder = index,
			})
		end
		sections.Affixes = e(Section, { title = "Affixes", layoutOrder = nextOrder(), children = rows })
	end

	if #view.baseStats > 0 then
		local rows: { [string]: any } = {}
		for index, stat in ipairs(view.baseStats) do
			rows[`Base{index}`] = e(Row, {
				label = stat.label,
				value = stat.value,
				role = "MutedText",
				layoutOrder = index,
			})
		end
		sections.BaseStats = e(Section, { title = "Base Stats", layoutOrder = nextOrder(), children = rows })
	end

	if #view.requirements > 0 then
		local rows: { [string]: any } = {}
		for index, req in ipairs(view.requirements) do
			-- The point of this panel's rework: an unmet requirement is visibly unmet, and the
			-- player's current value is shown so the gap is obvious.
			local role = if req.met == false
				then "RequirementUnmet"
				elseif req.met == true then "RequirementMet"
				else "MutedText"
			local value = if req.current ~= nil
				then `{req.required}  (you: {math.floor(req.current)})`
				else tostring(req.required)
			rows[`Req{index}`] = e(Row, {
				label = req.label,
				value = value,
				role = role,
				layoutOrder = index,
			})
		end
		sections.Requirements = e(Section, { title = "Requirements", layoutOrder = nextOrder(), children = rows })
	end

	-- Actions mirror the old panel's availability rules exactly (Guardrail 1: capabilities are
	-- preserved even though presentation changed).
	local meta = item and item.meta or nil
	local function flag(key: string): boolean
		return meta ~= nil and meta[key] == true
	end
	local locked = flag("locked") or flag("bound")

	local actions: { [string]: any } = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, theme.metrics.paddingSm),
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
		}),
	}
	local actionOrder = 0
	local function addAction(id: string, label: string, enabled: boolean, run: () -> ())
		actionOrder += 1
		actions[id] = e(Button, {
			text = label,
			enabled = enabled,
			onActivated = run,
			layoutOrder = actionOrder,
			size = UDim2.new(0, 110, 1, 0),
		})
	end

	if def and EquipmentDefUtils.getEquipSlots(def) and location and location.container == "inventory" then
		addAction("Equip", "Equip", not locked and not flag("noEquip"), function()
			local slot = ItemActions.pickEquipSlot(def, inventory.equipment)
			if slot and location then
				ItemActions.equip(location.slot, slot)
			end
		end)
	end
	if location and location.container == "equipment" then
		addAction("Unequip", "Unequip", not locked and not flag("noUnequip"), function()
			if location then
				ItemActions.unequip(location.slot)
			end
		end)
	end
	if def and def.useAction and item then
		addAction("Use", "Use", not locked and not flag("noUse"), function()
			ItemActions.use(item.uid)
		end)
	end
	if item and location and location.container == "inventory" and not flag("noDrop") then
		addAction("Drop", "Throw", not locked, function()
			ItemActions.drop(item.uid)
		end)
	end

	local pad = theme.metrics.paddingMd

	return e(PanelShell, { gap = pad, padding = pad }, {
		-- The well spans the panel; the icon field inside it is a fixed square, so it is the same
		-- size for every item regardless of the icon's native shape.
		IconWell = e(Panel, {
			role = "PanelBlock",
			stroke = true,
			layoutOrder = 1,
			size = UDim2.new(1, 0, 0.22, 0),
			padding = theme.metrics.paddingSm,
		}, {
			Field = e(Icon, { image = view.icon }),
		}),

		TitleBar = e(Header, {
			title = view.displayName,
			layoutOrder = 2,
			color = RARITY_COLORS[view.rarity],
		}),

		Details = e(ScrollList, {
			layoutOrder = 3,
			fill = true,
			stroke = true,
			padding = pad,
			gap = theme.metrics.paddingMd,
		}, sections),

		Actions = if actionOrder > 0
			then e("Frame", {
				LayoutOrder = 4,
				Size = UDim2.new(1, 0, 0.08, 0),
				BackgroundTransparency = 1,
			}, actions)
			else nil,
	})
end

return ItemCard
