--!strict
-- Renders one item's details: icon well, title bar, scrolling info, action bar.
--
-- Presentational and driven entirely by `uid` -- or an `item` handed over directly, for one that is
-- not in the bag, like a drop on the ground -- so it has no opinion about *why* an item is being
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

local Brackets = require(script.Parent.Parent.Parent.components.Brackets)
local StatList = require(script.Parent.Parent.Parent.components.StatList)
local Glyph = require(script.Parent.Parent.Parent.components.Glyph)
local PanelShell = require(script.Parent.Parent.Parent.components.PanelShell)
local Header = require(script.Parent.Parent.Parent.components.Header)
local Icon = require(script.Parent.Parent.Parent.components.Icon)
local Text = require(script.Parent.Parent.Parent.components.Text)
local Button = require(script.Parent.Parent.Parent.components.Button)
local ScrollList = require(script.Parent.Parent.Parent.components.ScrollList)

local ThemeContext = require(script.Parent.Parent.Parent.hooks.ThemeContext)
local useInventory = require(script.Parent.Parent.Parent.hooks.useInventory)
local useAttributes = require(script.Parent.Parent.Parent.hooks.useAttributes)
local useProgression = require(script.Parent.Parent.Parent.hooks.useProgression)

local ItemActions = require(script.Parent.Parent.Parent.actions.ItemActions)
local Selector = require(script.Parent.Parent.Parent.selectors.itemInspect)

local Registry = require(ReplicatedStorage.Shared.items.Registry)
local CharacterXP = require(ReplicatedStorage.Shared.progression.CharacterXP)
local ItemTypes = require(ReplicatedStorage.Shared.items.ItemTypes)
local EquipmentDefUtils = require(ReplicatedStorage.Shared.items.EquipmentDefUtils)

local e = React.createElement

export type Props = {
	-- Which item to inspect. nil renders the empty state.
	uid: string?,
	-- An item that is not in the bag, shown as-is.
	item: ItemTypes.ItemInstance?,
	-- No action bar: the item is shown, not acted on (a drop is taken by clicking its label).
	readOnly: boolean?,
}

local Section = StatList.Section
local Row = StatList.Row

local function ItemCard(props: Props)
	local theme = ThemeContext.useTheme()
	local inventory = useInventory()
	local attributes = useAttributes()
	local progression = useProgression()
	local level = if progression then CharacterXP.levelOf(progression.characterXp) else nil

	local item = props.item or (if props.uid then inventory.items[props.uid] else nil)
	local view = Selector.buildView(item, attributes, level)

	if not view.found then
		return e(PanelShell, nil, {
			Empty = e(Text, {
				text = "No item selected",
				role = "MutedText",
				alignX = Enum.TextXAlignment.Center,
				size = UDim2.fromScale(1, 1),
				textSize = theme.type.body,
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
		-- Equipped but below its requirements (the gear lending it attributes came off, or they were
		-- reset): it stays on, giving nothing, until they are met again.
		local status = if location and location.container == "equipment" and inventory.projection
			then inventory.projection.items
			else nil
		for _, entry in ipairs(status or {}) do
			if entry.uid == props.uid and not entry.active then
				rows.Inactive = e(Row, {
					label = "Status",
					value = "Inactive",
					role = "RequirementUnmet",
					layoutOrder = 0,
				})
			end
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
			size = UDim2.new(0, 96, 1, 0),
			variant = if actionOrder == 1 then "primary" else "secondary",
			textSize = theme.type.small,
		})
	end

	local requirementsMet = true
	for _, req in ipairs(view.requirements) do
		if req.met == false then
			requirementsMet = false
		end
	end
	if def and EquipmentDefUtils.getEquipSlots(def) and location and location.container == "inventory" then
		addAction("Equip", "Equip", not locked and not flag("noEquip") and requirementsMet, function()
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
	if def and def.useAction and item and location then
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
	local tint = (theme.rarity :: any)[view.rarity]
	local hasIcon = view.icon ~= nil and view.icon ~= ""

	return e(PanelShell, { gap = 10, padding = pad }, {
		-- The well spans the panel; the icon field inside it is a fixed square, so it is the same
		-- size for every item regardless of the icon's native shape. Rarity lights the well from
		-- below, the same language as a slot, so the card reads as that slot enlarged.
		IconWell = e("Frame", {
			LayoutOrder = 1,
			Size = UDim2.new(1, 0, 0, 120),
			BackgroundColor3 = theme.color.surfaceRaised,
			BackgroundTransparency = 0.4,
			BorderSizePixel = 0,
		}, {
			Brackets = e(Brackets, { size = "small", color = tint }),
			Glow = if tint
				then e("Frame", {
					Size = UDim2.fromScale(1, 0.55),
					AnchorPoint = Vector2.new(0, 1),
					Position = UDim2.fromScale(0, 1),
					BackgroundColor3 = tint,
					BorderSizePixel = 0,
				}, {
					Fade = e("UIGradient", {
						Rotation = -90,
						Transparency = NumberSequence.new({
							NumberSequenceKeypoint.new(0, 0.6),
							NumberSequenceKeypoint.new(1, 1),
						}),
					}),
				})
				else nil,
			Field = if hasIcon
				then e(Icon, { image = view.icon, size = UDim2.fromScale(0.8, 0.8) })
				-- Stand-in until items have icons, as in Slot.
				else e(Glyph, {
					glyph = view.glyph,
					color = tint or theme.color.stroke,
					thickness = 2,
					size = UDim2.fromScale(0.6, 0.6),
					position = UDim2.fromScale(0.5, 0.48),
				}),
		}),

		TitleBar = e(Header, {
			title = view.displayName,
			layoutOrder = 2,
			height = 0.07,
			color = tint,
		}),

		Details = e(ScrollList, {
			layoutOrder = 3,
			fill = true,
			padding = 4,
			gap = 12,
			corner = false,
		}, sections),

		Actions = if actionOrder > 0 and not props.readOnly
			then e("Frame", {
				LayoutOrder = 4,
				Size = UDim2.new(1, 0, 0, 34),
				BackgroundTransparency = 1,
			}, actions)
			else nil,
	})
end

return ItemCard
