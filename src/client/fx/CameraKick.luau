--!strict
-- CameraKick: brief turns of the gameplay camera that give a blow or a shot some weight -- a hit
-- jolts the view a degree or so and it springs back. CameraController applies the sum on top of the
-- pose it computes and takes it off again before the next frame's smoothing, so a kick never drifts
-- the aim.
--
-- Rotation only, about the camera's own position: nothing it frames moves relative to anything else.

local CameraKick = {}

-- Seconds to reach full strength. The rest of the duration eases back to rest.
local RISE = 0.03
-- Kicks overlapping in a flurry add up, but never past this many degrees on either axis.
local MAX_DEGREES = 3

type Kick = {
	pitch: number,
	yaw: number,
	startedAt: number,
	duration: number,
}

local kicks: { Kick } = {}

-- `pitch` (degrees, positive looks up) and `yaw` (degrees, positive turns left), returning to rest
-- over `duration` seconds.
function CameraKick.kick(pitch: number, yaw: number, duration: number)
	table.insert(kicks, { pitch = pitch, yaw = yaw, startedAt = os.clock(), duration = math.max(duration, RISE * 2) })
end

-- The rotation to apply this frame, relative to the camera's own frame.
function CameraKick.current(): CFrame
	if #kicks == 0 then
		return CFrame.identity
	end
	local now = os.clock()
	local pitch, yaw = 0, 0
	for index = #kicks, 1, -1 do
		local kick = kicks[index]
		local age = now - kick.startedAt
		if age >= kick.duration then
			table.remove(kicks, index)
			continue
		end
		local strength = if age < RISE
			then age / RISE
			else (1 - (age - RISE) / (kick.duration - RISE)) ^ 2
		pitch += kick.pitch * strength
		yaw += kick.yaw * strength
	end
	pitch = math.clamp(pitch, -MAX_DEGREES, MAX_DEGREES)
	yaw = math.clamp(yaw, -MAX_DEGREES, MAX_DEGREES)
	return CFrame.Angles(math.rad(pitch), math.rad(yaw), 0)
end

return CameraKick
