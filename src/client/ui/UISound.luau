--!strict
-- Plays the UI's sound cues (shared/Config/UISoundConfig) on the client, through one sound group so
-- the UI can be mixed as a whole.
--
-- Each cue is a Sound made once and fired with PlayLocalSound, which plays an independent copy, so a
-- cue can overlap itself. Repeats inside `minInterval` are dropped.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local SharedConfig = require(ReplicatedStorage.Shared.Config)

local CONFIG = SharedConfig.UISound

local UISound = {}

type Cue = { id: string, volume: number, speed: number? }

local group: SoundGroup? = nil
local sounds: { [string]: Sound } = {}
local lastPlayed: { [string]: number } = {}

local function getGroup(): SoundGroup
	if group and group.Parent then
		return group
	end
	local made = Instance.new("SoundGroup")
	made.Name = "UI"
	made.Volume = CONFIG.volume
	made.Parent = SoundService
	group = made
	return made
end

local function soundFor(key: string, cue: Cue): Sound
	local sound = sounds[key]
	if sound and sound.Parent then
		return sound
	end
	local made = Instance.new("Sound")
	made.Name = `UI_{key}`
	made.SoundId = cue.id
	made.Volume = cue.volume
	made.PlaybackSpeed = cue.speed or 1
	made.SoundGroup = getGroup()
	made.Parent = getGroup()
	sounds[key] = made
	return made
end

local function play(key: string, cue: Cue?)
	if not cue then
		return
	end
	local now = os.clock()
	if now - (lastPlayed[key] or 0) < CONFIG.minInterval then
		return
	end
	lastPlayed[key] = now
	SoundService:PlayLocalSound(soundFor(key, cue))
end

-- "hover" | "confirm" | "open" | "close" | "notify" | "error" | "ready"
function UISound.play(name: string)
	play(name, CONFIG.cues[name])
end

-- The pickup stinger for an item of this rarity.
function UISound.pickup(rarity: string?)
	local key = rarity or "normal"
	play(`pickup_{key}`, CONFIG.pickup[key] or CONFIG.pickup.normal)
end

return UISound
