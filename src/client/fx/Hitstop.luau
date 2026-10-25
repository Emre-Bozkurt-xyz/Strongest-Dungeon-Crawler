--!strict
-- Hitstop: freezes the caster's swing for a few frames when a melee hit connects, so the hit reads
-- as a weapon meeting a body instead of passing through it. Local only; the server's timeline does
-- not stop, and the pause is short enough that the swing stays inside its combo window.

local Hitstop = {}

local DEFAULT_DURATION = 0.06

-- Tracks frozen right now, with the speed to restore and the freeze that owns them.
local frozen: { [AnimationTrack]: { speed: number, token: {} } } = {}

function Hitstop.apply(track: AnimationTrack?, duration: number?)
	if not track or not track.IsPlaying then
		return
	end
	local existing = frozen[track]
	local speed = if existing then existing.speed else track.Speed
	if speed == 0 then
		return
	end
	local token = {}
	frozen[track] = { speed = speed, token = token }
	track:AdjustSpeed(0)

	task.delay(duration or DEFAULT_DURATION, function()
		local entry = frozen[track]
		if not entry or entry.token ~= token then
			return
		end
		frozen[track] = nil
		-- Tracks are cached per animation and reused, so a track replayed during the freeze already
		-- has its new speed and must keep it.
		if track.IsPlaying and track.Speed == 0 then
			track:AdjustSpeed(entry.speed)
		end
	end)
end

return Hitstop
