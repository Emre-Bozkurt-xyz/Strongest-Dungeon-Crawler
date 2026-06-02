--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemTypes = require(ReplicatedStorage.Shared.items.ItemTypes)
local EquipmentDefUtils = require(ReplicatedStorage.Shared.items.EquipmentDefUtils)

local CapabilityResolver = {}

function CapabilityResolver.resolve(def: ItemTypes.ItemDef, item: ItemTypes.ItemInstance?): ItemTypes.ItemCapability
	local capability: ItemTypes.ItemCapability = {
		stats = {},
		attributes = {},
		skills = {},
		animationOverrides = {},
	}

	for _, entry in ipairs(EquipmentDefUtils.getBaseModifiers(def, item)) do
		if entry.meta and entry.meta.container == "attribute" then
			table.insert(capability.attributes :: { ItemTypes.ModifierEntry }, entry)
		else
			table.insert(capability.stats :: { ItemTypes.ModifierEntry }, entry)
		end
	end

	local staticCapabilities = EquipmentDefUtils.getCapabilities(def)
	if staticCapabilities then
		if staticCapabilities.stats then
			for _, entry in ipairs(staticCapabilities.stats) do
				table.insert(capability.stats :: { ItemTypes.ModifierEntry }, entry)
			end
		end
		if staticCapabilities.attributes then
			for _, entry in ipairs(staticCapabilities.attributes) do
				table.insert(capability.attributes :: { ItemTypes.ModifierEntry }, entry)
			end
		end
		if staticCapabilities.skills then
			for _, grant in ipairs(staticCapabilities.skills) do
				table.insert(capability.skills :: { ItemTypes.SkillGrant }, grant)
			end
		end
		if staticCapabilities.animationOverrides then
			for _, overrideEntry in ipairs(staticCapabilities.animationOverrides) do
				table.insert(capability.animationOverrides :: { ItemTypes.AnimationOverrideEntry }, overrideEntry)
			end
		end
	end

	local meta = item and item.meta or nil
	local affixes = meta and meta.affixes
	if affixes then
		for _, affix in ipairs(affixes) do
			local anyAffix = affix :: any
			if type(anyAffix) == "table" and anyAffix.modifiers then
				for _, entry in ipairs(anyAffix.modifiers) do
					if entry.target then
						if entry.meta and entry.meta.container == "attribute" then
							table.insert(capability.attributes :: { ItemTypes.ModifierEntry }, entry)
						else
							table.insert(capability.stats :: { ItemTypes.ModifierEntry }, entry)
						end
					end
				end
			elseif anyAffix.target then
				if anyAffix.meta and anyAffix.meta.container == "attribute" then
					table.insert(capability.attributes :: { ItemTypes.ModifierEntry }, anyAffix)
				else
					table.insert(capability.stats :: { ItemTypes.ModifierEntry }, anyAffix)
				end
			end
		end
	end

	return capability
end

return CapabilityResolver
