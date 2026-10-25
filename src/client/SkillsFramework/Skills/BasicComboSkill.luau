local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BaseSkill = require(script.Parent.BaseSkill)
local SkillPacer = require(script.Parent.Parent.SkillPacer)
local SkillMetadataClient = require(script.Parent.Parent.SkillMetadataClient)
local BasicAttackProfileRegistry = require(ReplicatedStorage.Shared.skills.BasicAttackProfileRegistry)
local CombatLoadoutMirror = require(script.Parent.Parent.Parent.Inventory.CombatLoadoutMirror)
local AimResolver = require(script.Parent.Parent.AimResolver)
local MeleeHits = require(ReplicatedStorage.Shared.skills.MeleeHits)
local AnimationPlayer = require(script.Parent.Parent.Parent.fx.AnimationPlayer)
local AnimationOverrideStore = require(script.Parent.Parent.Parent.Animation.AnimationOverrideStore)
local Networking = require(ReplicatedStorage.Shared.Networking)
local Schema = require(ReplicatedStorage.Shared.Debug.Schema)
local Clock = require(ReplicatedStorage.Shared.Time.Clock)
local DebugConfig = require(ReplicatedStorage.Shared.Debug.DebugConfig)

local dispatcher = Networking.client()

-- DEBUG FLAG: Set to true to enable combo flow logging
local DEBUG_COMBO = false

local function debugLog(...)
	if DEBUG_COMBO then
		print("[COMBO-DEBUG]", ...)
	end
end

-- A press arriving up to this long before it could be accepted is held and fired at that moment,
-- rather than dropped for being a few frames early. Earlier than this it is dropped, so a stray
-- early click does not commit the player to a swing they have since moved on from.
local INPUT_BUFFER = 0.25
-- A held press fires this long after its moment rather than on it. The server opens the same
-- window on its own clock, and a press landing exactly on the edge can reach it a hair early.
local BUFFER_RELEASE_MARGIN = 0.03
-- Rejections that clear by themselves shortly -- the current step or another action finishing, or
-- the server confirming the previous step -- and so are worth holding a press through.
local BUFFERABLE: { [string]: boolean } = {
	combo_busy = true,
	combo_complete = true,
	combo_pending = true,
	locked = true,
}

type BufferedPress = {
	releaseAt: number,
	expiresAt: number,
}

local BasicComboSkill = {}
BasicComboSkill.__index = BasicComboSkill
setmetatable(BasicComboSkill, { __index = BaseSkill })

function BasicComboSkill.new(name: string?, config: any?)
	local self = BaseSkill.new(name, config)
	setmetatable(self, BasicComboSkill)
	self._comboIdleTrack = nil :: AnimationTrack?
	self._comboIdleToken = nil :: string?
	self._bufferedPress = nil :: BufferedPress?
	self._bufferConn = nil :: RBXScriptConnection?
	self._replayingBuffer = false
	return self
end

function BasicComboSkill:_clearBufferedPress()
	self._bufferedPress = nil
	if self._bufferConn then
		self._bufferConn:Disconnect()
		self._bufferConn = nil
	end
end

-- Retry the held press each frame from its release time until it is accepted, refused for a reason
-- that will not clear, or expires.
function BasicComboSkill:_runBufferedPress()
	if self._bufferConn then
		return
	end
	self._bufferConn = RunService.Heartbeat:Connect(function()
		local press = self._bufferedPress
		local t = os.clock()
		if not press or t > press.expiresAt then
			self:_clearBufferedPress()
			return
		end
		if t < press.releaseAt then
			return
		end
		self._replayingBuffer = true
		local ok, err = pcall(self.use, self)
		self._replayingBuffer = false
		if not ok then
			self:_clearBufferedPress()
			warn("BasicComboSkill: buffered press failed:", err)
		end
	end)
end

-- Hold a refused press if it will be accepted soon; otherwise report the refusal.
function BasicComboSkill:_bufferOrReject(reason: string?)
	local bufferable = reason ~= nil and BUFFERABLE[reason] == true

	-- A replayed press that is still refused keeps waiting on its original deadline, silently.
	if self._replayingBuffer then
		if not bufferable then
			self:_clearBufferedPress()
		end
		return
	end

	if not bufferable then
		self:_clearBufferedPress()
		self:showRejectionFeedback(reason :: any)
		return
	end

	-- When the refusal names the moment it lifts, wait for that moment; otherwise (awaiting the
	-- server, another action) poll from now.
	local t = os.clock()
	local releaseAt = t
	local combo = SkillPacer.getComboState(self.name)
	if combo then
		if reason == "combo_busy" and combo.windowOpensAt then
			releaseAt = combo.windowOpensAt + BUFFER_RELEASE_MARGIN
		elseif reason == "combo_complete" then
			releaseAt = combo.chainEndsAt + BUFFER_RELEASE_MARGIN
		end
	end
	if releaseAt - t > INPUT_BUFFER then
		self:showRejectionFeedback(reason :: any)
		return
	end

	self._bufferedPress = { releaseAt = releaseAt, expiresAt = releaseAt + INPUT_BUFFER }
	self:_runBufferedPress()
end

function BasicComboSkill:_stopComboIdle()
	-- Clearing the token first invalidates any delayed start still in flight, so a scheduled idle
	-- cannot resurrect itself after the combo it belonged to has ended.
	self._comboIdleToken = nil
	local track = self._comboIdleTrack
	if track then
		self._comboIdleTrack = nil
		pcall(function()
			track:Stop(0.15)
		end)
	end
end

-- Hold `idleKey` looping from when the step animation ends until the chain window closes.
--
-- Scheduled rather than chained off the step track's Stopped signal: the step animation is played
-- with a predicted duration that may be scaled by attack speed, and Stopped also fires when the
-- next step interrupts it, which is exactly when the idle must NOT start.
function BasicComboSkill:_scheduleComboIdle(idleKey: string, startDelay: number, stopAfter: number)
	local token = tostring(os.clock()) .. "_" .. tostring(math.random(1, 1e6))
	self._comboIdleToken = token

	local resolvedKey = AnimationOverrideStore.resolve(idleKey, self.entityId)

	task.delay(math.max(startDelay, 0), function()
		if self._comboIdleToken ~= token then
			return
		end
		self._comboIdleTrack = AnimationPlayer.playLooped(resolvedKey)

		task.delay(math.max(stopAfter, 0), function()
			if self._comboIdleToken ~= token then
				return
			end
			self:_stopComboIdle()
		end)
	end)
end

-- Report a projectile step's release marker so the server fires the shot on the frame the animation
-- reaches it, instead of on the authored hit delay.
--
-- Fire-and-forget: the server is already holding an armed release with its own timeout, so a
-- dropped or late request costs the shot its timing, not the shot.
function BasicComboSkill:_bindReleaseMarker(markerName: string, step: number, attemptId: string?)
	local handle = self.currentAnimationHandle
	local track = handle and handle:getTrack()
	if not track then
		return
	end

	local conn
	conn = track:GetMarkerReachedSignal(markerName):Connect(function()
		if conn then
			conn:Disconnect()
			conn = nil
		end
		-- A newer swing has taken over; this marker belongs to an animation already superseded.
		if attemptId and self.currentAttemptId ~= attemptId then
			return
		end

		local payload = {
			skillName = self.name,
			userId = self.player.UserId,
			inputTime = Clock.serverNow(),
			attemptId = attemptId,
			comboStep = step,
		}
		if Schema.checkSkillRequest(payload) then
			dispatcher:request("SkillRequestMarker", payload)
		end
	end)

	self.markerEventListenerDestroyers[`release_{markerName}_{step}`] = function()
		if conn then
			conn:Disconnect()
			conn = nil
		end
	end
end

-- The looping animation to hold between combo steps, or nil for none.
-- Adaptive skills take it from the resolved weapon profile; static specs from `anim.comboIdle`.
function BasicComboSkill:_resolveComboIdleKey(profile: any?): string?
	if profile and type(profile.idleAnimation) == "string" and profile.idleAnimation ~= "" then
		return profile.idleAnimation
	end
	local anim = self.config.anim
	local comboIdle = anim and anim.comboIdle
	if type(comboIdle) == "string" and comboIdle ~= "" then
		return comboIdle
	end
	return nil
end

function BasicComboSkill:use()
	debugLog("========== USE CALLED ==========")
	debugLog("Skill:", self.name)

	-- Fetched regardless of adaptive/static path: cooldown/gcd below always come from the
	-- server-replicated skill metadata, only combo/anim shape branches on adaptiveBasicAttack.
	local metadata = SkillMetadataClient.get(self.name)

	local comboSteps
	local comboConfig
	local activeProfile = nil

	if self.config.adaptiveBasicAttack == true then
		-- Adaptive BasicAttack (D6, docs/tasks/equipment-item-architecture.md): resolve the same
		-- profile the server resolves, from the same mirrored combat loadout, instead of reading a
		-- static combo/anim off this spec. Additive -- the five other skills never set this flag
		-- and keep using the static path below unchanged (trap 3).
		local profile = BasicAttackProfileRegistry.resolve(CombatLoadoutMirror.get())
		activeProfile = profile
		local steps = {}
		for i, stepSpec in ipairs(profile.steps) do
			steps[i] = { key = stepSpec.animation }
		end
		comboSteps = steps
		comboConfig = profile.combo
		if DebugConfig.isEnabled("inputFlow") then
			print("[InputFlow]", `BasicComboSkill '{self.name}' resolved profile '{profile.id}'`)
		end
	else
		comboSteps = self.config.anim and self.config.anim.comboSteps
		comboConfig = (metadata and metadata.combo) or self.config.combo or {}
	end

	if not comboSteps or type(comboSteps) ~= "table" or #comboSteps == 0 then
		warn("BasicComboSkill: No combo steps configured for", self.name)
		return
	end

	-- Extract combo parameters from server config (should match ClientSpec)
	local totalSteps = comboConfig.steps or #comboSteps
	if totalSteps > #comboSteps then
		totalSteps = #comboSteps
	end
	debugLog("Total steps:", totalSteps)

	-- CHECK COMBO WINDOW TIMING (replicates server ComboService logic)
	debugLog("Checking canAdvance...")
	local canAdvance, comboReason, predictedStep, hasActiveCombo = SkillPacer.canAdvanceCombo(self.name, totalSteps)
	debugLog("canAdvance:", canAdvance, "reason:", comboReason or "none")
	if not canAdvance then
		self:_bufferOrReject(comboReason)
		return
	end

	-- PREDICT next combo step locally (instant, no server wait)
	debugLog("Predicted step:", predictedStep)

	-- PRE-FLIGHT CHECK: Validate local state before starting animation
	-- Pass predicted step for accurate resource cost check (combo steps may have different costs)
	-- Pass true for isComboAdvance to allow execution lock chaining if combo is active
	debugLog("hasActiveCombo:", hasActiveCombo)
	local canUse, rejectionReason = self:canUseLocally(predictedStep, hasActiveCombo)
	debugLog("canUseLocally:", canUse, "reason:", rejectionReason or "none")
	if not canUse then
		self:_bufferOrReject(rejectionReason)
		return
	end

	self:_clearBufferedPress()
	-- Any idle from the previous step belongs to a swing that is now over.
	self:_stopComboIdle()

	local _tempo, durationScale = self:predictTiming()
	local timing = SkillPacer.computeComboTiming(predictedStep, totalSteps, comboConfig, durationScale)
	local predictedStepDuration = timing.stepDuration
	local holdDuration = timing.holdDuration
	local windowOpensAt = timing.windowOpensAt
	local windowExpiresAt = timing.windowExpiresAt

	local cooldown = comboConfig.comboCooldown or (metadata and metadata.cooldown) or nil
	local gcd = metadata and metadata.gcd or nil
	SkillPacer.recordComboStep(
		self.name,
		predictedStep,
		totalSteps,
		windowOpensAt,
		windowExpiresAt,
		holdDuration,
		cooldown,
		gcd
	)

	-- IMMEDIATE CAST SOUND: Play before animation starts (no network wait)
	self:playCastSoundLocal()

	-- Get animation for predicted step
	local animSpec = comboSteps[predictedStep]
	local animKey = animSpec and animSpec.key or comboSteps[1].key

	-- Calculate predicted duration for this combo step
	local predictedDuration: number? = nil
	if predictedStepDuration > 0 then
		predictedDuration = predictedStepDuration
	end

	self:_predictSession({
		currentStep = predictedStep,
		totalSteps = totalSteps,
		windowOpensAt = windowOpensAt,
		windowExpiresAt = windowExpiresAt,
	}, holdDuration > 0 and holdDuration or nil, { comboActive = hasActiveCombo })

	-- PLAY ANIMATION IMMEDIATELY with predicted timing (instant feedback, no server wait)
	self:playAnimation(animKey, {
		duration = predictedDuration, -- may be nil, AnimationPlayer will use default
		step = predictedStep,
	})

	local predictedHit = activeProfile and MeleeHits.forProfileStep(activeProfile, predictedStep)
	if predictedHit then
		self:predictHits({ predictedHit }, durationScale)
	end

	-- Bound after playAnimation, which is what creates the track the marker lives on.
	local activeStepSpec = activeProfile and activeProfile.steps[predictedStep]
	if activeStepSpec and activeStepSpec.releaseMarker then
		self:_bindReleaseMarker(activeStepSpec.releaseMarker, predictedStep, self.currentAttemptId)
	end

	local idleKey = self:_resolveComboIdleKey(activeProfile)
	if idleKey then
		-- Only meaningful while another step can still follow; on the final step the chain is over
		-- and the character should return to its normal idle.
		local isFinalStep = predictedStep >= totalSteps
		if not isFinalStep and windowExpiresAt then
			local now = os.clock()
			self:_scheduleComboIdle(idleKey, predictedStepDuration, math.max(windowExpiresAt - now - predictedStepDuration, 0))
		end
	end

	-- Sampled at activation, not when the projectile leaves partway through the animation, so the
	-- shot goes where the player was pointing when they pressed. Sent for every adaptive basic
	-- attack rather than only projectile steps: the server picks the authoritative combo step, so
	-- gating on the predicted one would drop aim exactly when the two disagree.
	local extra: { [string]: any }? = nil
	if self.config.adaptiveBasicAttack == true then
		local aimPoint = AimResolver.getAimPoint()
		if aimPoint then
			extra = { aimPoint = aimPoint }
		end
	end

	-- REQUEST server validation with callbacks (non-blocking, happens in parallel)
	SkillPacer.markServerPending(self.name, predictedStep)
	self:requestUseAsync(function(data)
		SkillPacer.clearServerPending(self.name, predictedStep)
		-- Server confirmed - reconcile combo state
		local serverStep = data.step or 1
		if serverStep ~= predictedStep then
			warn(
				("[CLIENT-COMBO] %s - Step mismatch: predicted=%s server=%s"):format(
					self.name,
					tostring(predictedStep),
					tostring(serverStep)
				)
			)
		end
		SkillPacer.confirmComboStep(self.name, serverStep, totalSteps, holdDuration)

	end, function(reason)
		-- Server rejected (rare - only on desync or edge cases)
		debugLog("Server rejected skill use, reason:", reason)

		SkillPacer.clearServerPending(self.name, predictedStep)
		-- CRITICAL: Cancel local prediction to stop animation/FX/sound immediately
		self:_stopComboIdle()
		self:cancelLocalPrediction(reason)
		-- Note: cancelLocalPrediction already clears combo state and marks attempt rejected
	end, extra)
end

return BasicComboSkill
