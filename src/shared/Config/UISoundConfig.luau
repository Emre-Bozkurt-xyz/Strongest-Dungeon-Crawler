--!strict
-- The UI's sound set (client/ui/UISound). Every cue is from Roblox's own UI sound library, which any
-- experience may use; swap an id here to change a sound everywhere it plays.
--
-- `speed` is PlaybackSpeed, which pitches the sound: pickups rise with rarity so a rare drop sounds
-- like one before the notice is read.

export type Cue = {
	id: string,
	volume: number,
	speed: number?,
}

local UISoundConfig = {
	-- Master volume for the UI sound group.
	volume = 0.6,
	-- Seconds: the same cue fired again within this is dropped, so several panels opening together,
	-- or a cursor sweeping a grid, makes one sound rather than a burst.
	minInterval = 0.05,

	cues = {
		-- Roblox_UI_Small_Click
		hover = { id = "rbxassetid://15675032796", volume = 0.25 },
		-- Roblox_UI_Bright_Click
		confirm = { id = "rbxassetid://15675059323", volume = 0.6 },
		-- Roblox_UI_Sweep
		open = { id = "rbxassetid://15675046931", volume = 0.45, speed = 1.15 },
		-- Roblox_UI_Whoosh_02
		close = { id = "rbxassetid://15675028888", volume = 0.35, speed = 1.2 },
		-- Roblox_UI_Tonal_Stinger
		notify = { id = "rbxassetid://15675043410", volume = 0.4 },
		-- Roblox_UI_Whistle_Low
		error = { id = "rbxassetid://15675062723", volume = 0.5 },
		-- Roblox_UI_Small_Click, high and quiet: a skill coming off cooldown, mid-fight.
		ready = { id = "rbxassetid://15675032796", volume = 0.2, speed = 1.6 },
	} :: { [string]: Cue },

	-- Pickup notices, by rarity: the notify stinger pitched up as the drop gets rarer.
	pickup = {
		normal = { id = "rbxassetid://15675043410", volume = 0.35, speed = 1.0 },
		magic = { id = "rbxassetid://15675043410", volume = 0.4, speed = 1.12 },
		rare = { id = "rbxassetid://15675043410", volume = 0.5, speed = 1.25 },
		unique = { id = "rbxassetid://15675043410", volume = 0.6, speed = 1.4 },
	} :: { [string]: Cue },
}

return UISoundConfig
