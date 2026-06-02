--!strict
-- PanelTemplateSchema: canonical template contract for diegetic panel assets.

export type RequiredNode = {
	name: string,
	className: string,
	required: boolean,
}

export type PanelSchema = {
	panelId: string,
	templatePath: { string },
	requiredNodes: { RequiredNode },
}

local function req(name: string, className: string): RequiredNode
	return {
		name = name,
		className = className,
		required = true,
	}
end

local function opt(name: string, className: string): RequiredNode
	return {
		name = name,
		className = className,
		required = false,
	}
end

local Schema: { [string]: PanelSchema } = {
	SystemPanel = {
		panelId = "SystemPanel",
		templatePath = { "Assets", "WorldUI", "PanelTemplates", "SystemPanel" },
		requiredNodes = {
			req("WorldPart", "BasePart"),
			req("SurfaceGui", "SurfaceGui"),
			opt("Root", "Frame"),
			opt("StatusPanel", "Frame"),
			opt("AttributesPanel", "Frame"),
			opt("InfoPanel", "Frame"),
		},
	},
	InventoryPanel = {
		panelId = "InventoryPanel",
		templatePath = { "Assets", "WorldUI", "PanelTemplates", "InventoryPanel" },
		requiredNodes = {
			req("WorldPart", "BasePart"),
			req("SurfaceGui", "SurfaceGui"),
			opt("Root", "Frame"),
			opt("InventoryGrid", "ScrollingFrame"),
		},
	},
	EquipmentPanel = {
		panelId = "EquipmentPanel",
		templatePath = { "Assets", "WorldUI", "PanelTemplates", "EquipmentPanel" },
		requiredNodes = {
			req("WorldPart", "BasePart"),
			req("SurfaceGui", "SurfaceGui"),
			opt("Root", "Frame"),
			opt("EquipmentSlots", "Frame"),
		},
	},
	ItemInspectPanel = {
		panelId = "ItemInspectPanel",
		templatePath = { "Assets", "WorldUI", "PanelTemplates", "ItemInspectPanel" },
		requiredNodes = {
			req("WorldPart", "BasePart"),
			req("SurfaceGui", "SurfaceGui"),
			opt("Root", "Frame"),
			opt("ActionBar", "Frame"),
		},
	},
	WorldLootInspectPanel = {
		panelId = "WorldLootInspectPanel",
		templatePath = { "Assets", "WorldUI", "PanelTemplates", "WorldLootInspectPanel" },
		requiredNodes = {
			req("WorldPart", "BasePart"),
			req("SurfaceGui", "SurfaceGui"),
			opt("Root", "Frame"),
			opt("LootContainer", "ScrollingFrame"),
			opt("RowTemplate", "Frame"),
		},
	},
	StatusPreviewPanel = {
		panelId = "StatusPreviewPanel",
		templatePath = { "Assets", "WorldUI", "PanelTemplates", "StatusPreviewPanel" },
		requiredNodes = {
			req("WorldPart", "BasePart"),
			req("SurfaceGui", "SurfaceGui"),
			opt("Root", "Frame"),
			opt("StatusPanel", "Frame"),
		},
	},
}

local PanelTemplateSchema = {}

function PanelTemplateSchema.get(panelId: string): PanelSchema?
	return Schema[panelId]
end

function PanelTemplateSchema.list(): { PanelSchema }
	local out = {}
	for _, panelSchema in pairs(Schema) do
		table.insert(out, panelSchema)
	end
	table.sort(out, function(a, b)
		return a.panelId < b.panelId
	end)
	return out
end

return PanelTemplateSchema
