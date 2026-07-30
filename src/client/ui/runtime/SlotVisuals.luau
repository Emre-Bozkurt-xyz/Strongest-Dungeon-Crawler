--!strict
-- Shared inventory/equipment slot binding and visual application helpers.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemTypes = require(ReplicatedStorage.Shared.items.ItemTypes)
local PanelBinder = require(script.Parent.PanelBinder)

local SlotVisuals = {}

export type SlotNodes = {
	icon: ImageLabel?,
	name: TextLabel?,
	stack: TextLabel?,
	rarityFrame: GuiObject?,
	rarityImage: ImageLabel?,
	button: GuiButton?,
	defaultRarityVisible: boolean?,
	defaultRarityColor: Color3?,
	defaultRarityTransparency: number?,
	defaultRarityImage: string?,
	defaultRarityImageColor: Color3?,
	defaultRarityImageTransparency: number?,
}

local RARITY_COLORS = {
	normal = Color3.fromRGB(200, 200, 200),
	magic = Color3.fromRGB(88, 152, 255),
	rare = Color3.fromRGB(255, 210, 90),
	unique = Color3.fromRGB(220, 140, 60),
}

local function getStringAttribute(node: Instance, key: string): string?
	local value = node:GetAttribute(key)
	if type(value) == "string" and value ~= "" then
		return value
	end
	return nil
end

local function resolveRarityImage(slot: Instance, nodes: SlotNodes, rarity: ItemTypes.ItemRarity): string?
	local pascal = string.upper(string.sub(rarity, 1, 1)) .. string.sub(rarity, 2)
	local keySnake = `RarityImage_{rarity}`
	local keyPascal = `RarityImage{pascal}`
	local sources: { Instance } = { slot }
	if nodes.rarityFrame then
		table.insert(sources, nodes.rarityFrame)
	end
	if nodes.rarityImage then
		table.insert(sources, nodes.rarityImage)
	end
	for _, source in ipairs(sources) do
		local image = getStringAttribute(source, keySnake) or getStringAttribute(source, keyPascal)
		if image then
			return image
		end
	end
	return nil
end

function SlotVisuals.resolveItemRarity(item: ItemTypes.ItemInstance?, def: ItemTypes.ItemDef?): ItemTypes.ItemRarity
	local meta = item and item.meta or nil
	if meta and type(meta.rarity) == "string" then
		return meta.rarity :: ItemTypes.ItemRarity
	end
	if def and def.rarity then
		return def.rarity
	end
	return "normal"
end

function SlotVisuals.bind(slot: Instance): SlotNodes
	local binder = PanelBinder.new(slot)
	local icon = binder:find({ "Icon" }, "ImageLabel") :: ImageLabel?
	local name = binder:find({ "NameLabel" }, "TextLabel") :: TextLabel?
	local stack = binder:find({ "StackLabel" }, "TextLabel") :: TextLabel?
	local rarityNode = binder:find({ "RarityFrame" }, nil)
	local rarityFrame = if rarityNode and rarityNode:IsA("GuiObject") then rarityNode else nil
	local rarityImage = if rarityFrame
		then (PanelBinder.new(rarityFrame):find({ "Image", "BackgroundImage", "FrameImage" }, "ImageLabel") :: ImageLabel?)
		else nil
	local button = binder:find({ "Button", "TextButton", "ClickTarget", "Hitbox" }, "GuiButton") :: GuiButton?
	if (not rarityImage) and rarityFrame and rarityFrame:IsA("ImageLabel") then
		rarityImage = rarityFrame
	end
	return {
		icon = icon,
		name = name,
		stack = stack,
		rarityFrame = rarityFrame,
		rarityImage = rarityImage,
		button = button,
		defaultRarityVisible = if rarityFrame then rarityFrame.Visible else nil,
		defaultRarityColor = if rarityFrame then rarityFrame.BackgroundColor3 else nil,
		defaultRarityTransparency = if rarityFrame then rarityFrame.BackgroundTransparency else nil,
		defaultRarityImage = if rarityImage then rarityImage.Image else nil,
		defaultRarityImageColor = if rarityImage then rarityImage.ImageColor3 else nil,
		defaultRarityImageTransparency = if rarityImage then rarityImage.ImageTransparency else nil,
	}
end

function SlotVisuals.applyRarityVisual(slot: Instance, nodes: SlotNodes, rarity: ItemTypes.ItemRarity?)
	local rarityFrame = nodes.rarityFrame
	local rarityImage = nodes.rarityImage
	local isEquipmentSlot = type(slot:GetAttribute("EquipmentSlot")) == "string"
	if not rarityFrame then
		return
	end

	if rarity then
		local color = RARITY_COLORS[rarity] or RARITY_COLORS.normal
		rarityFrame.Visible = true
		rarityFrame.BackgroundColor3 = color
		if rarityImage then
			rarityImage.Visible = true
			rarityImage.ImageColor3 = color
			local image = resolveRarityImage(slot, nodes, rarity)
			if image then
				rarityImage.Image = image
			end
		end
		return
	end

	if isEquipmentSlot then
		rarityFrame.Visible = if nodes.defaultRarityVisible == nil then true else nodes.defaultRarityVisible
		if nodes.defaultRarityColor then
			rarityFrame.BackgroundColor3 = nodes.defaultRarityColor
		end
		if nodes.defaultRarityTransparency then
			rarityFrame.BackgroundTransparency = nodes.defaultRarityTransparency
		end
		if rarityImage then
			rarityImage.Visible = rarityFrame.Visible
			if nodes.defaultRarityImageColor then
				rarityImage.ImageColor3 = nodes.defaultRarityImageColor
			end
			if nodes.defaultRarityImageTransparency then
				rarityImage.ImageTransparency = nodes.defaultRarityImageTransparency
			end
			if nodes.defaultRarityImage then
				rarityImage.Image = nodes.defaultRarityImage
			end
		end
		return
	end

	rarityFrame.Visible = false
	if rarityImage then
		rarityImage.Visible = false
	end
end

function SlotVisuals.setEmpty(slot: Instance, nodes: SlotNodes)
	if nodes.icon then
		nodes.icon.Image = ""
		nodes.icon.Visible = false
	end
	if nodes.name then
		nodes.name.Text = ""
		nodes.name.Visible = false
	end
	if nodes.stack then
		nodes.stack.Text = ""
		nodes.stack.Visible = false
	end
	SlotVisuals.applyRarityVisual(slot, nodes, nil)
	slot:SetAttribute("ItemUid", nil)
	slot:SetAttribute("ItemRarity", nil)
	slot:SetAttribute("ItemDisplayName", nil)
end

function SlotVisuals.setItem(slot: Instance, item: ItemTypes.ItemInstance, def: ItemTypes.ItemDef, nodes: SlotNodes)
	local displayName = if item.meta and type(item.meta.displayName) == "string" then item.meta.displayName else def.name
	if nodes.icon then
		nodes.icon.Image = def.icon or ""
		nodes.icon.Visible = nodes.icon.Image ~= ""
	end
	if nodes.name then
		nodes.name.Text = displayName
		nodes.name.Visible = displayName ~= ""
	end
	if nodes.stack then
		nodes.stack.Text = item.stackSize > 1 and tostring(item.stackSize) or ""
		nodes.stack.Visible = nodes.stack.Text ~= ""
	end
	local rarity = SlotVisuals.resolveItemRarity(item, def)
	SlotVisuals.applyRarityVisual(slot, nodes, rarity)
	slot:SetAttribute("ItemUid", item.uid)
	slot:SetAttribute("ItemRarity", rarity)
	slot:SetAttribute("ItemDisplayName", displayName)
end

return SlotVisuals
