--!strict
-- System notifications: the short messages the System sends the player ([ITEM ACQUIRED], errors).
-- See client/ui/controllers/NotificationClient and client/ui/panels/Notifications.

local NotificationsConfig = {
	-- Seconds a notice stays before it closes. A repeat of the same notice resets this.
	duration = 3.2,
	-- Notices shown at once; past this the oldest closes early.
	max = 4,
	-- Screen pixels from the top of the screen to the first notice, clear of Roblox's top bar.
	top = 72,
	gap = 6,
}

return NotificationsConfig
