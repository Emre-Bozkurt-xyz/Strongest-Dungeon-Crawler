local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Networking = require(ReplicatedStorage.Shared.Networking)

local AnimationPlayer = require(script.Parent.Parent.Parent.Client.fx.AnimationPlayer)
local FXPlayer = require(script.Parent.Parent.Parent.Client.fx.FXPlayer)
local ClientSpec = require(ReplicatedStorage.Shared.skills.ClientSpec)

local SkillsClient = {}

local SKILLS_CHANNEL_NAME = "Skills"
local dispatcher = Networking.client()
local dispatcherAny = dispatcher :: any
dispatcherAny:_ensureChannel(SKILLS_CHANNEL_NAME)

local activeComboIdle: { [number]: string } = {}

-- Track marker connections so we don't leak across replays
local markerConns: { [AnimationTrack]: { RBXScriptConnection } } = {}

-- Track active long-lived FX by caster and key so markers can stop them
type FXHandle = { Instance: Instance, Stop: () -> () }
local activeFX: { [number]: { [string]: FXHandle } } = {}

local function getFXMapForCaster(casterId: number?): { [string]: FXHandle }
	if not casterId then
		return {}
	end
	local m = activeFX[casterId]
	if not m then
		m = {}
		activeFX[casterId] = m
	end
	return m
end

local function clearMarkerConns(track: AnimationTrack)
	local list = markerConns[track]
	if list then
		for _, c in ipairs(list) do
			pcall(function()
				c:Disconnect()
			end)
		end
		markerConns[track] = nil
	end
end

local function playFXWithAnchor(key: string, casterId: number?, anchorSpec: any, lifetimeOverride: number?)
	local lifetime = lifetimeOverride or 1
	if anchorSpec and casterId then
		local plr = game.Players:GetPlayerByUserId(casterId)
		local char = plr and plr.Character
		if char then
			local att = anchorSpec.name and char:FindFirstChild(anchorSpec.name, true)
			if att and att:IsA("Attachment") then
				FXPlayer.playAttached(key, att, anchorSpec.offset, lifetime)
				return
			end
			-- If no attachment found, fall through to final fallback
		end
	end
	-- Final fallback
	FXPlayer.playAt(key, CFrame.new(), lifetime)
end

local function spawnFXWithAnchor(key: string, casterId: number?, anchorSpec: any): FXHandle?
	if anchorSpec and casterId then
		local plr = game.Players:GetPlayerByUserId(casterId)
		local char = plr and plr.Character
		if char then
			local att = anchorSpec.name and char:FindFirstChild(anchorSpec.name, true)
			if att and att:IsA("Attachment") then
				return FXPlayer.spawnAttached(key, att, anchorSpec.offset)
			end
			-- If no attachment, fall back to world spawn
		end
	end
	return FXPlayer.spawnAt(key, CFrame.new())
end

-- Resolve anchor for a given step from fx config, with optional override
local function resolveAnchorForStep(fxCfg: any, stepIdx: number?, override: any?): any
	if override then
		return override
	end
	if not fxCfg then
		return nil
	end
	local anchorsByStep = fxCfg.anchorsByStep
	if type(anchorsByStep) == "table" and stepIdx then
		local a = anchorsByStep[stepIdx]
		if a then
			return a
		end
	end
	return fxCfg.anchor
end

local function bindMarkerFX(track: AnimationTrack?, casterId: number?, markersSpec: any, fxCfg: any, stepIdx: number?)
	if not track or type(markersSpec) ~= "table" then
		return
	end
	-- Clear old connections for this track
	clearMarkerConns(track)
	markerConns[track] = {}
	for markerName, val in pairs(markersSpec) do
		local fxKey: string? = nil
		local lifetime: number? = nil
		local action: string = "play" -- play (one-shot), start, stop
		local anchorOverride: any = nil
		if type(val) == "string" then
			fxKey = val
			action = "play"
		elseif type(val) == "table" then
			fxKey = (val.key or val.fx or val[1]) :: string?
			lifetime = val.lifetime :: number?
			local vact = val.action or (val.start and "start") or (val.stop and "stop")
			if type(vact) == "string" then
				action = vact
			end
			anchorOverride = val.anchor
		end
		if fxKey then
			local conn = track:GetMarkerReachedSignal(markerName):Connect(function(_param)
				local anchorToUse = resolveAnchorForStep(fxCfg, stepIdx, anchorOverride)
				if action == "start" then
					local m = getFXMapForCaster(casterId)
					local existing = m[fxKey :: string]
					if existing then
						pcall(existing.Stop)
						m[fxKey :: string] = nil
					end
					local handle = spawnFXWithAnchor(fxKey :: string, casterId, anchorToUse)
					if handle then
						m[fxKey :: string] = handle :: FXHandle
					end
				elseif action == "stop" then
					local m = getFXMapForCaster(casterId)
					local h = m[fxKey :: string]
					if h then
						pcall(h.Stop)
						m[fxKey :: string] = nil
					end
				else
					playFXWithAnchor(fxKey :: string, casterId, anchorToUse, lifetime)
				end
			end)
			table.insert(markerConns[track], conn)
		end
	end
	-- Auto-clean up when track stops/ends
	table.insert(
		markerConns[track],
		track.Stopped:Connect(function()
			clearMarkerConns(track)
		end)
	)
	table.insert(
		markerConns[track],
		track.Ended:Connect(function()
			clearMarkerConns(track)
		end)
	)
end

local function onSkillsEvent(payload: any, _meta: any?)
	local phase = payload and payload.phase
	local id = payload and payload.id
	local spec = id and ClientSpec[id]
	if not phase or not id or not spec then
		return
	end

	local casterId = payload.casterId
	local localPlayer = Players.LocalPlayer
	local localUserId = localPlayer and localPlayer.UserId or nil
	local isLocalCaster = (typeof(casterId) == "number" and casterId == localUserId)

	if (phase == "start" or phase == "step" or phase == "combo_wait" or phase == "end" or phase == "interrupt") and not isLocalCaster then
		return
	end
	if phase == "start" then
		local anim = spec.anim and spec.anim.start
		local startKey: string? = nil
		if type(anim) == "string" then
			startKey = anim
		elseif type(anim) == "table" then
			startKey = anim[1]
		end
		if startKey then
			local track = AnimationPlayer.playReturn(startKey)
			local markersSpec = spec.fx and (spec.fx.markers or spec.fx.marker or spec.fx.markerFX)
			if markersSpec then
				bindMarkerFX(track, payload.casterId, markersSpec, spec.fx, nil)
			end
		end
	elseif phase == "step" then
		local idx = (payload.step or 1) :: number
		-- Per-step body animation: prefer anim.comboSteps; fallback to legacy anim.impact string/table
		local stepAnims = spec.anim and spec.anim.comboSteps
		local legacyImpactAnim = (spec.anim and spec.anim.impact) --[[deprecated for animations]]
		local animKeyToPlay: string? = nil
		if type(stepAnims) == "table" then
			animKeyToPlay = stepAnims[idx] or stepAnims[1]
		elseif type(legacyImpactAnim) == "table" then
			animKeyToPlay = legacyImpactAnim[idx] or legacyImpactAnim[1]
		elseif type(legacyImpactAnim) == "string" then
			animKeyToPlay = legacyImpactAnim
		end
		local track: AnimationTrack? = nil
		if animKeyToPlay then
			track = AnimationPlayer.playReturn(animKeyToPlay)
		end

		-- Bind marker-driven FX for this step animation, if configured
		local markersSpec = spec.fx and (spec.fx.markers or spec.fx.marker or spec.fx.markerFX)
		if markersSpec then
			bindMarkerFX(track, payload.casterId, markersSpec, spec.fx, idx)
		end

		-- Optional: start-of-step FX (wind/trail) defined in ClientSpec.fx.step
		local stepFx = spec.fx and spec.fx.step
		local resolvedStepFx: string? = nil
		if type(stepFx) == "table" then
			resolvedStepFx = stepFx[idx] or stepFx[1]
		elseif type(stepFx) == "string" then
			resolvedStepFx = stepFx
		end
		if resolvedStepFx then
			local anchorToUse = resolveAnchorForStep(spec.fx, idx, nil)
			playFXWithAnchor(resolvedStepFx, payload.casterId, anchorToUse, nil)
		end
	elseif phase == "fx" then
		local idx = (payload.step or 1) :: number
		local anchor = payload.anchor
		local lifetime = payload.lifetime or 1
		local fxKeyOverride = payload.fxKey
		local resolvedFx: string? = fxKeyOverride
		if not resolvedFx then
			local impactFx = spec.fx and spec.fx.impact
			if type(impactFx) == "table" then
				resolvedFx = impactFx[idx] or impactFx[1]
			elseif type(impactFx) == "string" then
				resolvedFx = impactFx
			end
		end
		if not resolvedFx then
			return
		end
		local finalCFrame = payload.cframe or CFrame.new()

		-- If no explicit anchor provided by server, try to resolve one from ClientSpec
		if not anchor then
			local autoAnchor = spec.fx and resolveAnchorForStep(spec.fx, idx, nil)
			if autoAnchor then
				playFXWithAnchor(resolvedFx, payload.casterId, autoAnchor, lifetime)
				return
			end
		end
		if anchor and anchor.mode == "attachment" then
			if casterId then
				local plr = game.Players:GetPlayerByUserId(casterId)
				local char = plr and plr.Character
				if char then
					local att = char:FindFirstChild(anchor.name, true)
					if att and att:IsA("Attachment") then
						FXPlayer.playAttached(resolvedFx, att, anchor.offset, lifetime)
						return
					end
					if anchor.fallback then
						local part = char:FindFirstChild(anchor.fallback)
						if part and part:IsA("BasePart") then
							finalCFrame = (part :: BasePart).CFrame
						end
					end
				end
			end
		end
		FXPlayer.playAt(resolvedFx, finalCFrame, lifetime)
	elseif phase == "combo_wait" then
		local open = payload.open
		local idleKey = spec.anim and spec.anim.comboIdle
		if open then
			if type(idleKey) == "string" then
				AnimationPlayer.play(idleKey)
				if casterId then
					activeComboIdle[casterId] = idleKey
				end
			end
		else
			if casterId and activeComboIdle[casterId] then
				AnimationPlayer.stop(activeComboIdle[casterId])
				activeComboIdle[casterId] = nil
			end
		end
	elseif phase == "end" or phase == "interrupt" then
		local finishAnim = spec.anim and spec.anim.finish
		if type(finishAnim) == "string" then
			AnimationPlayer.play(finishAnim)
		elseif type(finishAnim) == "table" then
			local k2 = finishAnim[1]
			if k2 then
				AnimationPlayer.play(k2)
			end
		end
		-- Ensure any lingering loop FX for this caster are stopped
		if casterId and activeFX[casterId] then
			for key, handle in pairs(activeFX[casterId]) do
				pcall(handle.Stop)
				activeFX[casterId][key] = nil
			end
		end
	end
end

dispatcherAny:on("SkillsEvent", onSkillsEvent)

function SkillsClient.useSkill(skillName: string)
	task.spawn(function()
		local ok, resultOrError = pcall(function()
			return dispatcherAny:request("SkillsRequest", {
				action = "use",
				skillName = skillName,
			}, {
				qos = "CRITICAL",
			})
		end)
		if not ok then
			warn("SkillsClient: Failed to request skill use:", resultOrError)
			return
		end
		local res = resultOrError
		if typeof(res) == "table" and res.success == false then
			warn("SkillsClient: Skill request rejected:", res.error)
		end
	end)
end

return SkillsClient
