--!strict
-- Global configuration registry for tunable gameplay/UI values.

return {
	Camera = require(script.CameraConfig),
	WorldGUI = require(script.WorldGUIConfig),
	UIMenu = require(script.UIMenuConfig),
	ItemInspect = require(script.ItemInspectConfig),
	WorldLootInspect = require(script.WorldLootInspectConfig),
	-- Combat config removed in Phase B: the unarmed base now lives in the unarmed_basic
	-- BasicAttackProfile (src/shared/skills/BasicAttackProfiles/unarmed_basic.luau). See D6 in
	-- docs/tasks/equipment-item-architecture.md.
}
