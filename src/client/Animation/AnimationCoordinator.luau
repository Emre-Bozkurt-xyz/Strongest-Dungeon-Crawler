--!strict
-- Central coordinator for playing skill animations and publishing semantic marker events.
-- SkillsClient or other systems should call playSkillAnimation to play an animation; the
-- coordinator will emit skill-specific marker events that other systems (e.g. ProjectilesClient)
-- can subscribe to via onSkillMarker.

local Players = game:GetService("Players")

local AnimationPlayer = require(script.Parent.Parent.fx.AnimationPlayer)

local AnimationCoordinator = {}

-- listeners[skillName][markerName] = { fn, ... }
local listeners: { [string]: { [string]: { (ctx: any) -> () } } } = {}

-- active tracks to allow cleanup: track -> { skillName, options, connections = {RBXScriptConnection} }
local activeTracks: { [AnimationTrack]: any } = {}
local sessionTracks: { [string]: { [AnimationTrack]: boolean } } = {}

-- Internal helper to call listeners for a skill/marker with ctx
local function emitSkillMarker(skillName: string, markerName: string, ctx: any)
	local skillBucket = listeners[skillName]
	if not skillBucket then
		return
	end

	local handlers = skillBucket[markerName]
	if not handlers then
		return
	end
	for _, fn in ipairs(handlers) do
		local ok = pcall(fn, ctx)
		if not ok then
			warn("AnimationCoordinator handler for ", skillName, markerName, " failed")
		end
	end
end

local function trackSession(sessionId: string, track: AnimationTrack)
	if not sessionId or sessionId == "" then
		return
	end
	sessionTracks[sessionId] = sessionTracks[sessionId] or {}
	sessionTracks[sessionId][track] = true
	local info = activeTracks[track]
	if info then
		info.sessionId = sessionId
	end
end

function AnimationCoordinator.attachTrackToSession(track: AnimationTrack?, sessionId: string?)
	if not track or not sessionId or sessionId == "" then
		return
	end
	trackSession(sessionId, track)
end

function AnimationCoordinator.stopSession(sessionId: string, fade: number?)
	local bucket = sessionTracks[sessionId]
	if not bucket then
		return
	end
	for track in pairs(bucket) do
		if track and track.Parent then
			track:Stop(fade or 0.1)
		end
	end
	sessionTracks[sessionId] = nil
end

-- Subscribe to a skill marker. Returns disconnect function.
function AnimationCoordinator.onSkillMarker(skillName: string, markerName: string, fn: (ctx: any) -> ())
	assert(
		type(skillName) == "string" and type(markerName) == "string" and type(fn) == "function",
		"AnimationCoordinator.onSkillMarker: bad args"
	)
	listeners[skillName] = listeners[skillName] or {}
	listeners[skillName][markerName] = listeners[skillName][markerName] or {}
	table.insert(listeners[skillName][markerName], fn)
	local disconnected = false
	return function()
		if disconnected then
			return
		end
		disconnected = true
		local bucket = listeners[skillName] and listeners[skillName][markerName]
		if not bucket then
			return
		end
		for i = #bucket, 1, -1 do
			if bucket[i] == fn then
				table.remove(bucket, i)
				break
			end
		end
	end
end

-- Play a skill animation and wire marker events to the coordinator.
-- options: { fade?, speed?, duration?, markers?: {string} }
-- Pass markers array with marker names to listen for
function AnimationCoordinator.playSkillAnimation(skillName: string, animKey: string, options: { [string]: any }?): any
	local opts = (options or {}) :: any
	local track: AnimationTrack? = nil
	if opts.duration then
		track = AnimationPlayer.playTimed(animKey, {
			fade = opts.fade,
			duration = opts.duration,
		})
	else
		track = AnimationPlayer.playReturn(animKey, opts.fade :: number?, opts.speed :: number?)
	end
	if not track then
		return nil
	end

	-- store info for cleanup
	activeTracks[track] = { skillName = skillName, options = opts, connections = {} }
	if opts.sessionId then
		trackSession(opts.sessionId, track)
	end

	-- Set up GetMarkerReachedSignal for each marker if listeners are registered
	-- Modern Roblox uses GetMarkerReachedSignal(markerName), not KeyframeReached
	local skillBucket = listeners[skillName]
	if skillBucket then
		for markerName, handlers in pairs(skillBucket) do
			if #handlers > 0 then
				local markerConn = track:GetMarkerReachedSignal(markerName):Connect(function()
					local ctx = {
						skill = skillName,
						marker = markerName,
						ownerUserId = Players.LocalPlayer and Players.LocalPlayer.UserId or nil,
						character = Players.LocalPlayer and Players.LocalPlayer.Character or nil,
						partName = opts.partName,
						token = opts.token,
						markerTime = os.clock(),
						track = track,
						animationKey = animKey,
					}
					emitSkillMarker(skillName, markerName, ctx)
				end)
				table.insert(activeTracks[track].connections, markerConn)
			end
		end
	end

	-- cleanup when stopped
	local stoppedConn = track.Stopped:Connect(function()
		local info = activeTracks[track]
		if info and info.connections then
			for _, c in ipairs(info.connections) do
				c:Disconnect()
			end
		end
		if info and info.sessionId and sessionTracks[info.sessionId] then
			sessionTracks[info.sessionId][track] = nil
			if next(sessionTracks[info.sessionId]) == nil then
				sessionTracks[info.sessionId] = nil
			end
		end
		activeTracks[track] = nil
	end)
	table.insert(activeTracks[track].connections, stoppedConn)

	-- return a small handle so callers can stop manually
	local handle = {}
	function handle:stop(fade)
		track:Stop(fade or 0.1)
	end
	function handle:getTrack()
		return track
	end
	return handle
end

-- One-off wait helper (optional): waits for a single marker event or times out.
-- waitForMarker intentionally omitted to keep coordinator minimal; add later if needed.

return AnimationCoordinator
