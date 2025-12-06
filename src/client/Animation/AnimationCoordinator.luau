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

-- Internal helper to call listeners for a skill/marker with ctx
local function emitSkillMarker(skillName: string, markerName: string, ctx: any)
	print(`🔔 [ANIM-COORD] Marker fired: skill={skillName} marker={markerName}`)
	
	local skillBucket = listeners[skillName]
	if not skillBucket then
		print(`❌ [ANIM-COORD] No listeners for skill: {skillName}`)
		local availableSkills = {}
		for k in pairs(listeners) do
			table.insert(availableSkills, k)
		end
		print(`   Available skills: {table.concat(availableSkills, ", ")}`)
		return
	end
	
	local handlers = skillBucket[markerName]
	if not handlers then
		print(`❌ [ANIM-COORD] No handlers for marker: {markerName} in skill {skillName}`)
		local availableMarkers = {}
		for k in pairs(skillBucket) do
			table.insert(availableMarkers, k)
		end
		print(`   Available markers: {table.concat(availableMarkers, ", ")}`)
		return
	end
	
	print(`✅ [ANIM-COORD] Found {#handlers} handler(s) for {skillName}.{markerName}`)
	for _, fn in ipairs(handlers) do
		local ok = pcall(fn, ctx)
		if not ok then
			warn("AnimationCoordinator handler for ", skillName, markerName, " failed")
		end
	end
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
	print(`📝 [ANIM-COORD] Registered handler: skill={skillName} marker={markerName} (now {#listeners[skillName][markerName]} handlers)`)
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

	print(`🎬 [ANIM-COORD] Animation track loaded for {skillName}: IsPlaying={track.IsPlaying} Length={track.Length}`)

	-- Set up GetMarkerReachedSignal for each marker if listeners are registered
	-- Modern Roblox uses GetMarkerReachedSignal(markerName), not KeyframeReached
	local skillBucket = listeners[skillName]
	if skillBucket then
		for markerName, handlers in pairs(skillBucket) do
			if #handlers > 0 then
				print(`🔗 [ANIM-COORD] Connecting GetMarkerReachedSignal for marker: {markerName}`)
				local markerConn = track:GetMarkerReachedSignal(markerName):Connect(function()
					print(`🎯 [ANIM-COORD] Marker reached: {markerName} for skill={skillName}`)
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
