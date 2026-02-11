local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Networking = require(ReplicatedStorage.Shared.Networking)
local Players = game:GetService("Players")

local FXPlayer = require(script.Parent.Parent.Parent.fx.FXPlayer)
local AnimationCoordinator = require(script.Parent.Parent.Parent.Animation.AnimationCoordinator)
local ClientSpec = require(ReplicatedStorage.Shared.skills.ClientSpec)
local Replicator = require(script.Parent.Parent.Parent.fx.Replicator)
local ImmediateHitFeedback = require(script.Parent.Parent.Parent.fx.ImmediateHitFeedback)
local ActionPermissions = require(ReplicatedStorage.Shared.ActionPermissions)
local Schema = require(ReplicatedStorage.Shared.Debug.Schema)
local Clock = require(ReplicatedStorage.Shared.Time.Clock)
local SkillPacer = require(script.Parent.Parent.SkillPacer)
local ProjectilesClient = require(script.Parent.Parent.Parent.Services.ProjectilesClient)
local Registrar = require(script.Parent.Parent.Parent.Services.Registrar)

-- Client-side state mirrors
local CooldownClient = require(script.Parent.Parent.CooldownClient)
local _SkillMetadataClient = require(script.Parent.Parent.SkillMetadataClient) -- Reserved for future use
local StatsClient = require(script.Parent.Parent.Parent.StatsClient)

-- Attempt tracking and unified stats store
local PredictionController = require(script.Parent.Parent.PredictionController)
local ClientStatsStore = require(script.Parent.Parent.Parent.Stats.ClientStatsStore)

local dispatcher = Networking.client()
dispatcher:_ensureChannel("Skills")

local BaseSkill = {}
BaseSkill.__index = BaseSkill
local DEBUG_PREDICTION = false

-- Rejection reasons for user feedback
export type RejectionReason =
	"on_cooldown"
	| "on_gcd"
	| "locked"
	| "insufficient_resources"
	| "invalid_combo_window"
	| "unknown"

function BaseSkill.new(name: string?, config: any?)
	local self = {}
	setmetatable(self, BaseSkill)

	self.name = name or "Skill"

	self.fxPlayer = FXPlayer
	self.animationCoordinator = AnimationCoordinator
	self.clientSpec = ClientSpec

	self.player = Players.LocalPlayer
	self.entityId = Registrar.getEntityId(self.player.Character)

	self.config = config or {}
	self.fxMap = {} :: { [string]: any }
	self.markerEventListenerDestroyers = {}

	-- Track currently-playing predicted feedback so we can cancel immediately
	self.currentAnimationHandle = nil :: any
	self.currentCastSoundPart = nil :: BasePart?
	self.currentSessionId = nil :: string?

	-- Current attempt ID for this skill instance (if any)
	self.currentAttemptId = nil :: string?

	return self
end

function BaseSkill:use()
	warn("use() must not be called on base class directly")
end

-- Play cast sound immediately (no network wait)
-- Call this at the start of skill:use() after validation passes
function BaseSkill:playCastSoundLocal(castSoundsOverride: { string }?)
	-- Stop any previous cast sound part (avoid stacking)
	if self.currentCastSoundPart then
		pcall(function()
			self.currentCastSoundPart:Destroy()
		end)
		self.currentCastSoundPart = nil
	end

	local castSounds = castSoundsOverride or (self.config and self.config.castSounds)
	if not castSounds or type(castSounds) ~= "table" or #castSounds == 0 then
		return
	end

	self.currentCastSoundPart = ImmediateHitFeedback.onCastStart({
		castSounds = castSounds,
	})
end

function BaseSkill:_stopAllLocalLoopFX()
	for _, handle in pairs(self.fxMap) do
		pcall(handle.Stop)
	end
	self.fxMap = {}
end

function BaseSkill:_disconnectMarkerListeners()
	for _, destroyer in pairs(self.markerEventListenerDestroyers) do
		destroyer()
	end
	self.markerEventListenerDestroyers = {}
end

function BaseSkill:cancelLocalPrediction(reason: string?): boolean
	-- Early exit if no active prediction/session (avoid redundant cleanup)
	if not self.currentAttemptId and not self.currentSessionId then
		-- print(`[{self.name}] cancelLocalPrediction called but nothing active, skipping`)
		return false
	end

	if DEBUG_PREDICTION then
		print(`[{self.name}] CANCELLING LOCAL PREDICTION - Reason: {reason or "unknown"}`)
		print(`  - Animation: {self.currentAnimationHandle and "YES" or "NO"}`)
		print(`  - Sound: {self.currentCastSoundPart and "YES" or "NO"}`)
		print(`  - Attempt: {self.currentAttemptId or "none"}`)
	end

	-- Stop animation
	if self.currentAnimationHandle then
		pcall(function()
			self.currentAnimationHandle:stop(0.05)
		end)
		self.currentAnimationHandle = nil
	end

	-- Stop any loop FX started locally
	self:_stopAllLocalLoopFX()

	-- Stop cast sound if still playing
	if self.currentCastSoundPart then
		pcall(function()
			self.currentCastSoundPart:Destroy()
		end)
		self.currentCastSoundPart = nil
	end

	-- Prevent late marker callbacks if anything lingers
	self:_disconnectMarkerListeners()

	-- Mark attempt as rejected so attempt-based FX cleanup runs too
	if self.currentAttemptId then
		ProjectilesClient.cancelPredicted(self.currentAttemptId)
		PredictionController.reject(self.currentAttemptId, reason or "cancelled", self.name)
		self.currentAttemptId = nil
	else
		PredictionController.reject(nil, reason or "cancelled", self.name)
	end

	self.currentSessionId = nil
	return true
end

function BaseSkill:_attachSessionId(sessionId: string?)
	if not sessionId or sessionId == "" then
		return
	end
	self.currentSessionId = sessionId
	if self.currentAnimationHandle and self.currentAnimationHandle.getTrack then
		local track = self.currentAnimationHandle:getTrack()
		if track then
			self.animationCoordinator.attachTrackToSession(track, sessionId)
		end
	end
end

function BaseSkill:_predictSession(
	comboInfo: { currentStep: number, totalSteps: number, windowOpensAt: number?, windowExpiresAt: number? }?,
	predictedDuration: number?,
	attemptMetadata: { [string]: any }?
): string?
	local attemptId = PredictionController.beginLocal(self.name, self.entityId, comboInfo, predictedDuration, attemptMetadata)
	self.currentAttemptId = attemptId
	return attemptId
end

function BaseSkill:onSessionEnded(state: string, reason: string?)
	if state == "CANCELLED" then
		self:cancelLocalPrediction(reason or "cancelled")
		return
	end
	if state ~= "COMPLETED" then
		return
	end

	self:_stopAllLocalLoopFX()
	self:_disconnectMarkerListeners()
	self.currentAnimationHandle = nil
	self.currentCastSoundPart = nil

	if self.currentAttemptId then
		PredictionController.complete(self.currentAttemptId, reason or "completed")
		self.currentAttemptId = nil
	end

	self.currentSessionId = nil
end

function BaseSkill:_findAnchor(anchorName: string): Instance?
	local char = self.player.Character
	if not char then
		return nil
	end
	local anchor = char:FindFirstChild(anchorName, true)
	return anchor
end

function BaseSkill:playAnimation(animKey: string, opts: { [string]: any }?): AnimationTrack?
	-- If we already have a predicted track playing, stop it before starting a new one.
	if self.currentAnimationHandle then
		pcall(function()
			self.currentAnimationHandle:stop(0.05)
		end)
		self.currentAnimationHandle = nil
	end
	self:_stopAllLocalLoopFX()

	-- Clean up old marker event listeners
	self:_disconnectMarkerListeners()

	-- Bind marker events from config
	local fxConfig = (opts and opts.fx) or self.config.fx
	local hitSounds = (opts and opts.hitSounds) or self.config.hitSounds
	local markers = fxConfig and fxConfig.markers
	if markers then
		for markerName, val in pairs(markers) do
			local anchorName = (fxConfig and fxConfig.anchor and fxConfig.anchor.name) or "HumanoidRootPart"

			if fxConfig and fxConfig.anchorsByStep and opts and opts.step then
				local stepAnchor = fxConfig.anchorsByStep[opts.step]
				anchorName = (stepAnchor and stepAnchor.name) or anchorName
			end

			local anchor = self:_findAnchor(anchorName)

			-- Create a unique key for this FX instance (includes step for combo skills)
			local step = opts and opts.step or nil
			local fxMapKey = if step then `{val.key or val}_step{step}` else (val.key or val)

			-- Check if this is a hit marker (for immediate feedback)
			local isHitMarker = markerName == "Impact"
				or string.match(markerName, "_Land$") ~= nil
				or string.match(markerName, "_Hit$") ~= nil
				or (type(val) == "table" and val.isHitMarker == true)

			self.markerEventListenerDestroyers[markerName] = self:bindMarkerEvent(markerName, function(_ctx: any)
				-- IMMEDIATE HIT FEEDBACK: Trigger on hit markers
				if isHitMarker then
					local hitOpts = {
						hitSounds = hitSounds,
						coneAngle = self.config.hitConeAngle,
						coneRange = self.config.hitConeRange,
					}
					ImmediateHitFeedback.onImpactMarker(hitOpts)
				end

				-- FX handling (existing logic)
				if type(val) == "string" then
					-- One-shot FX - always play locally
					self.fxPlayer.playAttached(val, anchor)

					-- Replicate to other players (default true)
					Replicator.emitFX({
						entityId = self.entityId,
						fxKey = val,
						anchorName = anchorName,
						step = step,
					})
				elseif type(val) == "table" then
					local shouldReplicate = val.replicate ~= false -- default true

					if val.action == "start" then
						-- Stop any existing FX with this key before starting new one
						if self.fxMap[fxMapKey] then
							pcall(self.fxMap[fxMapKey].Stop)
							self.fxMap[fxMapKey] = nil
						end

						-- Spawn looped FX locally
						local handler = self.fxPlayer.spawnAttached(val.key, anchor, val.offset)
						self.fxMap[fxMapKey] = handler

						-- Replicate start to other players
						if shouldReplicate then
							Replicator.emitFX({
								entityId = self.entityId,
								fxKey = val.key,
								anchorName = anchorName,
								action = "start",
								step = step,
							})
						end
					elseif val.action == "stop" then
						-- Stop the FX for this specific step
						if self.fxMap[fxMapKey] then
							pcall(self.fxMap[fxMapKey].Stop)
							self.fxMap[fxMapKey] = nil
						end

						-- Replicate stop to other players
						if shouldReplicate then
							Replicator.emitFX({
								entityId = self.entityId,
								fxKey = val.key,
								anchorName = anchorName,
								action = "stop",
								step = step,
							})
						end
					else
						-- Default: one-shot with optional lifetime
						self.fxPlayer.playAttached(val.key, anchor, val.offset, val.lifetime)

						if shouldReplicate then
							Replicator.emitFX({
								entityId = self.entityId,
								fxKey = val.key,
								anchorName = anchorName,
								lifetime = val.lifetime,
								step = step,
							})
						end
					end
				end
			end)
		end
	end -- NOW play the animation after all marker handlers are registered
	local animHandler = self.animationCoordinator.playSkillAnimation(self.name, animKey, opts)
	self.currentAnimationHandle = animHandler
	return animHandler and animHandler:getTrack() or nil
end

function BaseSkill:bindMarkerEvent(markerName: string, callback: (ctx: any) -> ())
	return self.animationCoordinator.onSkillMarker(self.name, markerName, callback)
end

-- ============================================================================
-- GATING METHODS (Pre-flight validation using local cached state)
-- ============================================================================

-- Check if skill can be used locally (pre-flight validation)
-- Returns: success (boolean), rejectionReason (RejectionReason?)
-- isComboAdvance: true if this is a combo skill trying to advance to the next step
function BaseSkill:canUseLocally(comboStep: number?, isComboAdvance: boolean?): (boolean, RejectionReason?)
	-- Keep entityId fresh across respawns
	local liveEntityId = Registrar.getEntityId(self.player.Character)
	if type(liveEntityId) == "string" and liveEntityId ~= "" then
		self.entityId = liveEntityId
	end

	if SkillPacer.isLocked(self.name) then
		return false, "locked"
	end

	if not isComboAdvance then
		local canStart, reason = SkillPacer.canStart(self.name)
		if not canStart then
			return false, reason or "locked"
		end
	end

	-- Check action permissions (includes execution lock + blocking status effects)
	local permissions = ActionPermissions.client()
	if permissions then
		local canCast, reason = permissions:canCast(self.entityId, {
			skillName = self.name,
			isCombo = isComboAdvance == true,
		})
		if not canCast then
			-- Blocked by status effect or missing entity context
			return false, "locked"
		end
	end

	-- Check cooldown
	local cooldownRemaining = CooldownClient.getRemaining(self.name)
	if cooldownRemaining > 0 then
		return false, "on_cooldown"
	end

	-- Check global cooldown (GCD) - key must match server: "_GCD"
	local gcdRemaining = CooldownClient.getRemaining("_GCD")
	if gcdRemaining > 0 then
		return false, "on_gcd"
	end

	-- Check resources
	local hasResources, _costInfo = self:checkResourcesLocal(comboStep)
	if not hasResources then
		return false, "insufficient_resources"
	end

	return true, nil
end

-- Check if player has sufficient resources for skill
-- Returns: hasResources (boolean), costInfo (table?)
function BaseSkill:checkResourcesLocal(comboStep: number?): (boolean, { cost: number?, resource: string? }?)
	-- Use ClientStatsStore for unified affordability check
	local affordability = ClientStatsStore.canAfford(self.name, comboStep)

	if not affordability then
		warn(`[{self.name}] No skill metadata cached yet - blocking until metadata loads`)
		return false, { cost = 0, resource = "unknown" }
	end

	return affordability.affordable, {
		cost = affordability.cost,
		resource = affordability.resource,
	}
end

-- Show visual/audio feedback for rejection
function BaseSkill:showRejectionFeedback(reason: RejectionReason)
	-- TODO: Implement UI feedback
	-- - Flash cooldown overlay red
	-- - Play error sound
	-- - Show floating text ("Not enough mana!", "On cooldown!", etc.)

	warn("Skill rejected locally:", self.name, "Reason:", reason)

	-- Placeholder: Play error sound
	-- local SoundService = game:GetService("SoundService")
	-- local errorSound = SoundService:FindFirstChild("ErrorSound")
	-- if errorSound then errorSound:Play() end
end

-- ============================================================================
-- PREDICTION HELPERS
-- ============================================================================

-- Predict timing locally using client's cached stats
-- Returns: tempo (number), durationScale (number?)
function BaseSkill:predictTiming(): (number, number?)
	local SkillTimingResolver = require(ReplicatedStorage.Shared.skills.SkillTimingResolver)

	local stats = StatsClient.getCurrentStats()
	if not stats then
		return 1, nil -- fallback to 1.0 tempo if stats not loaded yet
	end

	local metadata = _SkillMetadataClient.get(self.name)
	local skillTags = (metadata and metadata.tags)
		or (self.config and (self.config.tags or self.config.categories))
		or nil

	-- Create stat lookup from client's cached stats
	local function statLookup(statType: any): number?
		-- Stats are directly accessible (e.g., stats.AttackSpeed, stats.Mana)
		local stat = (stats :: any)[statType]
		if stat and type(stat) == "table" and type(stat.value) == "number" then
			return stat.value
		end
		return nil
	end

	local result = SkillTimingResolver.resolve(skillTags, statLookup)
	return result.tempo, result.durationScale
end

-- Calculate predicted duration for animation
-- Returns: predictedDuration (number?)
function BaseSkill:predictDuration(): number?
	local metadata = _SkillMetadataClient.get(self.name)
	local baseDuration = self.config.baseDuration
		or (metadata and (metadata.baseDuration or metadata.executionDuration))
	if not baseDuration then
		return nil
	end

	local _tempo, durationScale = self:predictTiming()
	if not durationScale then
		return nil
	end

	return baseDuration * durationScale
end

-- ============================================================================
-- NETWORKING
-- ============================================================================

-- Request skill use from server (blocking)
-- Use requestUseAsync for non-blocking with callbacks
function BaseSkill:requestUse(attemptId: string?, extra: { [string]: any }?): any
	local payload = {
		skillName = self.name,
		userId = self.player.UserId,
		attemptId = attemptId,
		inputTime = Clock.serverNow(),
	}
	if extra and type(extra) == "table" then
		for k, v in pairs(extra) do
			payload[k] = v
		end
	end
	if not Schema.checkSkillRequest(payload) then
		return { success = false, error = "invalid_request" }
	end
	local response = dispatcher:request("SkillRequestUse", payload)
	return response
end

-- Request skill use from server (non-blocking with callbacks)
-- onConfirm: Called when server confirms skill use with response data
-- onReject: Called when server rejects skill use with error reason
function BaseSkill:requestUseAsync(
	onConfirm: ((data: any) -> ())?,
	onReject: ((reason: string) -> ())?,
	extra: { [string]: any }?
)
	task.spawn(function()
		local attemptId = self.currentAttemptId

		-- Transition current attempt to pending_server state
		PredictionController.markPending(attemptId)

		local response = self:requestUse(attemptId, extra)

		-- Handle nil response (server error or timeout)
		if not response then
			PredictionController.reject(attemptId, "server_error", self.name)
			if onReject then
				onReject("server_error")
			end
			return
		end

		if response.success then
			if response.data and response.data.sessionId then
				self:_attachSessionId(response.data.sessionId)
			end
			-- Server confirmed - update attempt state
			PredictionController.confirm(attemptId, response.data)
			if onConfirm then
				onConfirm(response.data or {})
			end
		else
			-- Server rejected - mark attempt as rejected
			PredictionController.reject(attemptId, response.error or "unknown", self.name)
			if onReject then
				onReject(response.error or "unknown")
			end
		end
	end)
end

return BaseSkill
