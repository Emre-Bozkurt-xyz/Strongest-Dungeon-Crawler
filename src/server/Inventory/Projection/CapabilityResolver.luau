--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemTypes = require(ReplicatedStorage.Shared.items.ItemTypes)
local EquipmentDefUtils = require(ReplicatedStorage.Shared.items.EquipmentDefUtils)

local CapabilityResolver = {}

-- Rolled modifiers (base modifiers + affixes) declare where they apply via `scope`. Route them
-- into the matching capability container, and skip "weapon"/"skill" scoped entries entirely --
-- those stay local to CombatLoadoutResolver and must never leak into global player stats.
local function projectModifier(capability: ItemTypes.ItemCapability, entry: ItemTypes.ModifierEntry)
	local scope = EquipmentDefUtils.resolveScope(entry)
	if not EquipmentDefUtils.isProjectedScope(scope) then
		return
	end
	if scope == "attribute" then
		table.insert(capability.attributes :: { ItemTypes.ModifierEntry }, entry)
	else
		table.insert(capability.stats :: { ItemTypes.ModifierEntry }, entry)
	end
end

function CapabilityResolver.resolve(def: ItemTypes.ItemDef, item: ItemTypes.ItemInstance?): ItemTypes.ItemCapability
	local capability: ItemTypes.ItemCapability = {
		stats = {},
		attributes = {},
		skills = {},
		animationOverrides = {},
	}

	-- Rolled base modifiers: scope-based container selection.
	for _, entry in ipairs(EquipmentDefUtils.getBaseModifiers(def, item)) do
		projectModifier(capability, entry)
	end

	-- Static authored capabilities declare their container by *which list they are in*
	-- (staticCapabilities.stats vs .attributes), not by scope. Do NOT route these through
	-- scope-based selection -- every unmarked attribute capability would silently
	-- re-classify as a stat.
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

	-- Rolled affix modifiers: scope-based container selection.
	local meta = item and item.meta or nil
	local affixes = meta and meta.affixes
	if affixes then
		for _, affix in ipairs(affixes) do
			local anyAffix = affix :: any
			if type(anyAffix) == "table" and anyAffix.modifiers then
				for _, entry in ipairs(anyAffix.modifiers) do
					if entry.target then
						projectModifier(capability, entry)
					end
				end
			elseif anyAffix.target then
				projectModifier(capability, anyAffix :: ItemTypes.ModifierEntry)
			end
		end
	end

	return capability
end

return CapabilityResolver
