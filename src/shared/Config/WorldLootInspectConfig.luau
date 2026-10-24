--!strict
-- Tuning for nearby loot -- the plates and list (client/ui/panels/NearbyLoot) -- and server pickup
-- and drop rules.

local WorldLootInspectConfig = {
	hideWhenMenuOpen = true,
	scanInterval = 0.08,
	maxDistance = 10,
	maxVisibleRows = 6,
	-- Per-drop name plates, drawn while few enough drops are in range to read them where they lie.
	-- Past `limit`, a list over the nearest drop takes over so a big pile reads at a glance.
	labels = {
		limit = 5,
		-- Studs above the drop's centre.
		height = 1.4,
		-- Per second; how quickly a plate settles when stacking moves it.
		followRate = 20,
		-- Screen pixels between stacked plates.
		gap = 3,
	},
	selectionWrap = true,
	interaction = {
		pickupKey = Enum.KeyCode.E,
	},
	server = {
		pickupDistance = 10,
		claimDuration = 2.5,
		-- Omit despawn by default; set a positive number later if we decide loot should expire.
		dropForwardDistance = 3.0,
		-- Studs; drops land at random within this radius of the point ahead.
		dropScatterRadius = 1.5,
		dropHeightOffset = 1.5,
		dropGroundProbeHeight = 3.0,
		dropGroundProbeLength = 12.0,
	},
}

return WorldLootInspectConfig
