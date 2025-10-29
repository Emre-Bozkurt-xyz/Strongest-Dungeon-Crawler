--!strict
-- ProjectilesClient: listens to server projectile events and renders visuals locally with pooling

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local _Players = game:GetService("Players")

local Networking = require(ReplicatedStorage.Shared.Networking)
local FXPlayer = require(script.Parent.Parent.fx.FXPlayer)

local ProjectilesClient = {}

local dispatcher = Networking.client()
local dispatcherAny = dispatcher :: any
dispatcherAny:_ensureChannel("Projectiles")

-- Config
local INTERPOLATION_DELAY = 0.18 -- seconds (client will render ~180ms behind receive time)
local MAX_EXTRAPOLATION = 0.12 -- seconds
local EXTRAPOLATION_DISABLE_TIME = 0.12 -- seconds after spawn we avoid extrapolating (prevent early overshoot)
local _SNAP_THRESHOLD = 3 -- studs
local BUFFER_SIZE = 6
local _SERVER_OFFSET_ALPHA = 0.08
local _serverTimeOffset = 0.0 -- clientLocalTime - serverTime (smoothed)
local CORRECTION_DURATION = 0.12 -- seconds to lerp large corrections instead of snapping
-- Debugging: set to true to enable verbose projectile logs (spawn/update/render decisions)
local DEBUG_PROJECTILES = true
local DEBUG_LOG_LIMIT = 200 -- max log lines to avoid spamming
local _debugCount = 0

-- Focused event logging (only log important events to diagnose jitter)
local EVENT_LOG_LIMIT = 80
local _eventCounts: { [string]: number } = {}

local function _logEvent(evType: string, ...: any)
	if not DEBUG_PROJECTILES then
		return
	end
	_eventCounts[evType] = (_eventCounts[evType] or 0) + 1
	if _eventCounts[evType] > EVENT_LOG_LIMIT then
		return
	end
	local args = { ... }
	-- concise formatting
	-- build message manually
	local parts = {}
	for i, v in ipairs(args) do
		parts[i] = tostring(v)
	end
	print(string.format("[ProjectilesClient EVENT] %s: %s", evType, table.concat(parts, " ")))
end

local function _dbg(...: any)
	if not DEBUG_PROJECTILES then
		return
	end
	if _debugCount >= DEBUG_LOG_LIMIT then
		return
	end
	_debugCount += 1
	print("[ProjectilesClient DEBUG]", ...)
end

local function _dumpBuffer(buf: { any })
	local parts = {}
	for i, s in ipairs(buf) do
		parts[i] = string.format("[%d] t=%.3f pos=(%.2f,%.2f,%.2f)", i, s.recv, s.pos.X, s.pos.Y, s.pos.Z)
	end
	return table.concat(parts, "; ")
end

-- Pools and active visuals
local pools: { [string]: { Instance } } = {}
local visuals: { [number]: any } = {}

-- Parent folder for visuals
local VIS_ROOT = Workspace:FindFirstChild("Projectiles")
if not VIS_ROOT then
	VIS_ROOT = Instance.new("Folder")
	VIS_ROOT.Name = "Projectiles"
	VIS_ROOT.Parent = Workspace
end

local function acquireVisual(templateKey: string)
	local pool = pools[templateKey]
	if pool and #pool > 0 then
		local inst = table.remove(pool)
		return inst
	end
	-- Try to resolve template in ReplicatedStorage.Assets.Projectiles
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local projFolder = assets and assets:FindFirstChild("Projectiles")
	if projFolder then
		local tpl = projFolder:FindFirstChild(templateKey)
		if tpl then
			local clone = tpl:Clone()
			-- Ensure primary parts/anchored are ready for client-driven CFrame updates
			if clone:IsA("Model") then
				local primary = clone.PrimaryPart
				if primary then
					primary.Anchored = true
					primary.CanCollide = false
				end
			elseif clone:IsA("BasePart") then
				clone.Anchored = true
				clone.CanCollide = false
			end
			return clone
		end
	end
	-- Fallback: create a small visual part
	local fallback = Instance.new("Part")
	fallback.Size = Vector3.new(0.2, 0.2, 0.6)
	fallback.Shape = Enum.PartType.Block
	fallback.Anchored = true
	fallback.CanCollide = false
	fallback.Name = "ProjectileFallback"
	return fallback
end

local function releaseVisual(templateKey: string, inst: Instance)
	inst.Parent = nil
	pools[templateKey] = pools[templateKey] or {}
	table.insert(pools[templateKey], inst)
end

local function createVisualEntry(id: number, templateKey: string, cframe: CFrame, velocity: Vector3, seedRecv: number?)
	local inst = acquireVisual(templateKey)
	assert(inst, "createVisualEntry: failed to acquire visual instance")
	inst.Parent = VIS_ROOT
	if inst:IsA("Model") then
		local primary = inst.PrimaryPart
		if primary then
			primary.CFrame = cframe
		else
			-- try PivotTo as fallback
			pcall(inst.PivotTo, inst, cframe)
		end
	elseif inst:IsA("BasePart") then
		inst.CFrame = cframe
	end

	local entry = {
		id = id,
		inst = inst,
		templateKey = templateKey,
		buffer = {}, -- { { recv = os.clock(), pos = Vector3, vel = Vector3 } }
		lastPos = cframe.Position,
		lastForward = if velocity and velocity.Magnitude > 0.001 then velocity.Unit else Vector3.new(0, 0, 1),
	}
	-- Seed the buffer with a small backfilled sample + the actual spawn sample so we interpolate smoothly
	local now = os.clock()
	local vel = velocity or Vector3.new()
	local recv = now
	if seedRecv then
		recv = seedRecv
	end
	local backfill = math.min(0.06, INTERPOLATION_DELAY * 0.5)
	-- older sample slightly before spawn (prevents duplicate timestamps and avoids forward snaps)
	table.insert(entry.buffer, { recv = recv - backfill, pos = cframe.Position, vel = vel })
	table.insert(entry.buffer, { recv = recv, pos = cframe.Position, vel = vel })
	-- remember spawn time (mapped recv) so we can avoid extrapolating too early
	entry.spawnTime = recv
	visuals[id] = entry
	return entry
end

local function destroyVisualEntry(id: number)
	local entry = visuals[id]
	if not entry then
		return
	end
	local inst = entry.inst
	visuals[id] = nil
	-- return to pool
	releaseVisual(entry.templateKey or "", inst)
end

-- Insert a sample into buffer (keeps it ordered and trimmed)
local function pushSample(entry: any, pos: Vector3, vel: Vector3, recvOverride: number?, seqOverride: number?)
	local recv = recvOverride or os.clock()
	local s = { recv = recv, pos = pos, vel = vel, seq = seqOverride }
	-- detect out-of-order or duplicate samples
	local last = entry.buffer[#entry.buffer]
	if last then
		if recv == last.recv then
			_logEvent("sample_duplicate", entry.id, string.format("t=%.3f", recv))
		elseif recv < last.recv then
			_logEvent("sample_earlier", entry.id, string.format("t=%.3f last=%.3f", recv, last.recv))
		end
	end
	-- detect seq ordering if present
	if seqOverride then
		if entry.lastSeq and seqOverride <= entry.lastSeq then
			_logEvent("sample_seq_older", entry.id, string.format("seq=%d last=%d", seqOverride, entry.lastSeq))
		end
		entry.lastSeq = seqOverride
	end
	table.insert(entry.buffer, s)
	-- trim
	while #entry.buffer > BUFFER_SIZE do
		table.remove(entry.buffer, 1)
	end
end

-- Interpolate/extrapolate to compute render position
-- returns pos, vel, mode where mode is "interp", "extrap", or "latest"
local function computeRenderPosition(entry: any): (Vector3, Vector3, string)
	local now = os.clock()
	local renderTime = now - INTERPOLATION_DELAY
	local buf = entry.buffer
	if #buf == 0 then
		return entry.lastPos, Vector3.new(), "latest"
	end
	-- find surrounding samples
	local A = nil
	local B = nil
	for i = 1, #buf - 1 do
		local s1 = buf[i]
		local s2 = buf[i + 1]
		if s1.recv <= renderTime and renderTime <= s2.recv then
			A = s1
			B = s2
			break
		end
	end
	if A and B and A ~= B then
		local denom = (B.recv - A.recv)
		local alpha = 0
		if denom > 0 then
			alpha = (renderTime - A.recv) / denom
		end
		local pos = A.pos:Lerp(B.pos, alpha)
		local vel = A.vel:Lerp(B.vel, alpha)
		return pos, vel, "interp"
	end
	-- otherwise, use latest sample and extrapolate if needed
	local latest = buf[#buf]
	local dt = renderTime - latest.recv
	if dt <= 0 then
		-- we're rendering at or before latest sample time; no extrapolation
		if entry and entry.lastExtrap then
			entry.lastExtrap = false
			_logEvent("extrap_end", entry.id)
		end
		return latest.pos, latest.vel, "latest"
	end
	local originalDt = dt
	-- Avoid extrapolating aggressively right after spawn: use latest sample until buffer has aged
	if entry and entry.spawnTime then
		local sinceSpawn = latest.recv - entry.spawnTime
		if sinceSpawn < EXTRAPOLATION_DISABLE_TIME then
			-- do not extrapolate yet, just show latest authoritative sample
			_logEvent("extrap_disabled", entry.id, string.format("sinceSpawn=%.3f reqDt=%.3f", sinceSpawn, originalDt))
			dt = 0
		end
	end
	if dt > MAX_EXTRAPOLATION then
		dt = MAX_EXTRAPOLATION
	end
	local mode = "extrap"
	if dt > 0 then
		if not entry.lastExtrap then
			entry.lastExtrap = true
			_logEvent("extrap_start", entry.id, string.format("dt=%.3f", dt))
		end
	else
		mode = "latest"
		if entry and entry.lastExtrap then
			entry.lastExtrap = false
			_logEvent("extrap_end", entry.id)
		end
	end
	local pos = latest.pos + latest.vel * dt
	return pos, latest.vel, mode
end

-- Render loop: update visuals each frame
RunService.RenderStepped:Connect(function(_dt)
	for _, entry in pairs(visuals) do
		local inst = entry.inst
		if inst and inst.Parent then
			local pos, vel, mode = computeRenderPosition(entry)
			local forward = entry.lastForward
			if vel and vel.Magnitude > 0.001 then
				forward = vel.Unit
				entry.lastForward = forward
			else
				local dir = pos - entry.lastPos
				if dir.Magnitude > 0.001 then
					forward = dir.Unit
					entry.lastForward = forward
				end
			end

			-- first-render logging: capture how we first place the visual (interp/extrap/latest)
			if not entry.firstRendered then
				entry.firstRendered = true
				local prev = entry.lastPos
				local delta = (pos - prev).Magnitude
				_logEvent("first_render", entry.id, mode, string.format("delta=%.3f", delta), _dumpBuffer(entry.buffer))
			end

			-- Focused snap detection: only log when a large correction (snap) occurs
			if DEBUG_PROJECTILES then
				local prev = entry.lastPos
				local delta = (pos - prev).Magnitude
				if delta > _SNAP_THRESHOLD then
					local bufFirst = entry.buffer[1]
					local bufLast = entry.buffer[#entry.buffer]
					-- Only emit a snap log when we don't already have an active correction
					-- or when the snap magnitude increased substantially (to avoid per-frame spam).
					local shouldLogSnap = false
					if not entry.correction then
						shouldLogSnap = true
					else
						local lastSnap = entry._lastSnapDelta or 0
						if delta > lastSnap * 1.2 then
							shouldLogSnap = true
						end
					end
					if shouldLogSnap then
						_logEvent(
							"snap",
							entry.id,
							string.format("delta=%.3f", delta),
							string.format(
								"first_t=%.3f pos=(%.2f,%.2f,%.2f)",
								bufFirst and bufFirst.recv or 0,
								bufFirst and bufFirst.pos.X or 0,
								bufFirst and bufFirst.pos.Y or 0,
								bufFirst and bufFirst.pos.Z or 0
							),
							string.format(
								"last_t=%.3f pos=(%.2f,%.2f,%.2f)",
								bufLast and bufLast.recv or 0,
								bufLast and bufLast.pos.X or 0,
								bufLast and bufLast.pos.Y or 0,
								bufLast and bufLast.pos.Z or 0
							)
						)
						entry._lastSnapDelta = delta
					end

					-- compute a dynamic correction duration based on projectile speed and delta
					local speed = (bufLast and bufLast.vel and bufLast.vel.Magnitude) or 0
					local dur = CORRECTION_DURATION
					if speed > 0 then
						-- time needed to cover 'delta' at 'speed' (scaled), clamped to reasonable bounds
						dur = math.clamp((delta / speed) * 0.6, 0.06, 0.5)
					end
					if not entry.correction then
						entry.correction = { start = entry.lastPos, target = pos, t0 = os.clock(), dur = dur }
						_logEvent("correction_start", entry.id, string.format("delta=%.3f dur=%.3f", delta, dur))
					else
						-- refresh: continue smoothing from the current interpolated correction position
						local now = os.clock()
						local elapsed = now - entry.correction.t0
						local p = math.clamp(elapsed / entry.correction.dur, 0, 1)
						local currentPos = entry.correction.start:Lerp(entry.correction.target, p)
						entry.correction.start = currentPos
						entry.correction.target = pos
						entry.correction.t0 = now
						entry.correction.dur = dur
						_logEvent("correction_refresh", entry.id, string.format("delta=%.3f dur=%.3f", delta, dur))
					end
				end
			end
			-- apply correction if active: override pos with lerped value
			if entry.correction then
				local now = os.clock()
				local elapsed = now - entry.correction.t0
				local p = math.clamp(elapsed / entry.correction.dur, 0, 1)
				local corrected = entry.correction.start:Lerp(entry.correction.target, p)
				pos = corrected
				if p >= 1 then
					_logEvent("correction_end", entry.id)
					entry.correction = nil
				end
			end
			local lookAtCf = CFrame.lookAt(pos, pos + forward)
			if inst:IsA("Model") then
				local primary = inst.PrimaryPart
				if primary then
					primary.CFrame = lookAtCf
				else
					pcall(inst.PivotTo, inst, lookAtCf)
				end
			elseif inst:IsA("BasePart") then
				inst.CFrame = lookAtCf
			end

			entry.lastPos = pos
		end
	end
end)

-- Networking handler
dispatcher:on("ProjectileEvent", function(payload: any, _meta: any)
	if type(payload) ~= "table" then
		return
	end
	local phase = payload.phase
	-- Update server->client offset if server timestamp provided
	if payload.t and type(payload.t) == "number" then
		local measured = os.clock() - payload.t
		_serverTimeOffset = _serverTimeOffset * (1 - _SERVER_OFFSET_ALPHA) + measured * _SERVER_OFFSET_ALPHA
		_dbg("measured offset=", string.format("%.4f", measured), "smoothed=", string.format("%.4f", _serverTimeOffset))
	end

	if phase == "spawn" then
		local id = payload.id
		local template = payload.template or ""
		local cframe = payload.cframe or CFrame.new()
		local velocity = payload.velocity or Vector3.new()
		local seedRecv = nil
		if payload.t and type(payload.t) == "number" then
			seedRecv = payload.t + _serverTimeOffset
		end
		_logEvent(
			"spawn",
			id,
			"tpl=" .. tostring(template),
			"pos=" .. tostring(cframe.Position),
			"vel=" .. tostring(velocity),
			"seedRecv=" .. tostring(seedRecv)
		)
		local entry = createVisualEntry(id, template, cframe, velocity, seedRecv)
		-- If the server provided an authoritative initial sample, keep it in the buffer with seq
		if payload.initial and type(payload.initial) == "table" then
			local init = payload.initial
			local initPos = init.position or cframe.Position
			local initVel = init.velocity or velocity
			-- seedRecv already maps payload.t -> client local time; use same recv time for init
			if seedRecv then
				pushSample(entry, initPos, initVel, seedRecv, init.seq)
			else
				pushSample(entry, initPos, initVel, nil, init.seq)
			end
		end
	elseif phase == "update" then
		local updates = payload.updates
		if type(updates) == "table" then
			local sampleRecv = nil
			if payload.t and type(payload.t) == "number" then
				sampleRecv = payload.t + _serverTimeOffset
			end
			for _, u in ipairs(updates) do
				local id = u.id
				local entry = visuals[id]
				if entry then
					_logEvent("update", id, "seq=" .. tostring(u.seq or "?"), "recv=" .. tostring(sampleRecv))
					pushSample(entry, u.position or entry.lastPos, u.velocity or Vector3.new(), sampleRecv, u.seq)
				else
					-- If we get an update for an unknown projectile, create a fallback visual
					local tpl = payload.template or ""
					local cf = CFrame.new(u.position or Vector3.new())
					_logEvent(
						"update_new",
						id,
						"seq=" .. tostring(u.seq or "?"),
						"pos=" .. tostring(u.position),
						"recv=" .. tostring(sampleRecv)
					)
					local newEntry = createVisualEntry(id, tpl, cf, u.velocity or Vector3.new(), sampleRecv)
					-- keep the update sample (with seq)
					pushSample(newEntry, u.position or newEntry.lastPos, u.velocity or Vector3.new(), sampleRecv, u.seq)
				end
			end
		end
	elseif phase == "destroy" then
		local id = payload.id
		destroyVisualEntry(id)
	elseif phase == "hit" then
		-- Play hit FX immediately at the server-provided position
		local pos = payload.pos
		local fxKey = payload.fxKey or (payload.extraData and payload.extraData.fx)
		if pos and fxKey then
			FXPlayer.playAt(fxKey, CFrame.new(pos))
		elseif pos then
			-- generic hit FX if configured
			FXPlayer.playAt("Impact", CFrame.new(pos))
		end
	end
end)

return ProjectilesClient
