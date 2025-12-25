local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SkillsConfig = require(script.Parent.SkillsConfig)
local Networking = require(ReplicatedStorage.Shared.Networking)
local ActionPermissions = require(ReplicatedStorage.Shared.ActionPermissions)
local CooldownService = require(script.Parent.CooldownService)
local SessionManager = require(script.Parent.SessionManager) -- Phase 3.6: Unified system (legacy removed)
local Registrar = require(game.ServerScriptService.Server.Services.Registrar)

local SkillsManager = {}

type Caster = string

local casterSkills: { [Caster]: { [string]: any } } = {} -- Table to hold skills per caster
local permissions = ActionPermissions.server()

-- Forward declare type for function without defining it
local useSkill: (caster: Caster, skillName: string, requestData: any?) -> ()

local SKILLS_CHANNEL_NAME = "Skills"
local dispatcher = Networking.server()
local dispatcherAny = dispatcher :: any
dispatcherAny:_ensureChannel(SKILLS_CHANNEL_NAME)

local function sendDelta(caster: Caster, type: string, data: any?)
	local player = Registrar.getPlayerById(caster)
	if player then
		dispatcher:emit("SkillsUpdate", {
			updateType = type,
			data = data,
		}, {
			targets = player,
		})
	end
end

function SkillsManager.addSkill(caster: Caster, name: string, override: SkillsConfig.SkillConfigOverride?)
	local skill = SkillsConfig.addSkill(caster, name, override)
	casterSkills[caster] = casterSkills[caster] or {}
	casterSkills[caster][name] = skill

	sendDelta(caster, "skill_added", {
		skillName = name,
	})

	return skill
end

-- DEBUG FLAG: Set to true to enable skill use logging
local DEBUG_SKILLS = false
local DEBUG_PHASE3 = false

local function debugLog(...: any)
	if DEBUG_SKILLS then
		print("[SERVER-SKILLS]", ...)
	end
end

local function debugPhase3(...: any)
	if DEBUG_PHASE3 then
		print("[PHASE3-SKILLS]", ...)
	end
end

-- Phase 3.6: Listen for session completion to start cooldown + GCD
-- This replaces the ExecutionService.onCompleted listener
local function shouldStartCooldownOnCancel(skill: any, reason: string?): boolean
	if reason == "insufficient_resources" then
		return false
	end
	if skill.config and skill.config.cooldownOnCancel ~= nil then
		return skill.config.cooldownOnCancel == true
	end
	return true
end

local function startCooldowns(casterId: string, skillName: string, skill: any)
	if skill.gcd and skill.gcd > 0 then
		CooldownService.startGCD(casterId, skill.gcd)
	end
	if skill.cooldown and skill.cooldown > 0 then
		CooldownService.start(casterId, skillName, skill.cooldown)
	end
end

local function onSessionEnded(session: any, state: string, reason: string?)
	debugLog("========== SessionEnded ==========")
	debugLog("Caster:", session.casterId, "Skill:", session.skillId, "State:", state, "Reason:", reason or "none")

	local skills = casterSkills[session.casterId]
	if not skills then
		debugLog("No skills found for caster")
		return
	end
	local skill = skills[session.skillId]
	if not skill then
		debugLog("Skill not found:", session.skillId)
		return
	end

	if state == "COMPLETED" then
		startCooldowns(session.casterId, session.skillId, skill)
	elseif state == "CANCELLED" then
		if shouldStartCooldownOnCancel(skill, reason) then
			startCooldowns(session.casterId, session.skillId, skill)
		else
			debugLog("Skipping cooldown on cancel for", session.skillId, "reason:", reason or "none")
		end
	end
end

-- Connect to SessionManager state changes
local _sessionStateDisconnect = SessionManager.listen("stateChanged", function(session: any, newState: string, reason: string?)
	if newState ~= "COMPLETED" and newState ~= "CANCELLED" then
		return
	end

	local skills = casterSkills[session.casterId]
	local skill = skills and skills[session.skillId] or nil

	if skill and skill.onSessionEnded then
		skill:onSessionEnded(session.id, newState, reason)
	end

	if newState == "COMPLETED" or newState == "CANCELLED" then
		onSessionEnded(session, newState, reason)
	end
end)

function SkillsManager.canUse(caster: Caster, skillName: string): (boolean, string?)
	debugLog("========== canUse ==========")
	debugLog("Caster:", caster, "Skill:", skillName)

	local skills = casterSkills[caster]
	if not skills then
		debugLog("REJECTED: no_skills")
		return false, "no_skills"
	end

	local skill = skills[skillName]
	if not skill then
		debugLog("REJECTED: no_skill")
		return false, "no_skill"
	end

	local skillCfg = skill.config or SkillsConfig.skills[skillName]
	local comboCfg = skillCfg and skillCfg.combo
	debugLog("Has comboCfg:", comboCfg ~= nil)

	-- Block if main skill cooldown active (cooldown gating between full uses)
	local onCD = CooldownService.isOnCooldown(caster, skillName)
	if onCD then
		debugLog("REJECTED: on_cooldown")
		return false, "on_cooldown"
	end

	-- Check if entity can cast (status effects, death, execution lock)
	-- Pass combo info so ActionPermissions can allow combo chaining
	local canCast, reason = permissions:canCast(caster, {
		skillName = skillName,
		isCombo = comboCfg ~= nil,
	})
	if not canCast then
		debugLog("REJECTED: canCast failed, reason:", reason)
		return false, reason
	end

	debugLog("PASSED: can use")
	return true
end

function SkillsManager.useSkill(caster: Caster, skillName: string, requestData: any?): any
	debugLog("========== useSkill ==========")
	debugLog("Caster:", caster, "Skill:", skillName)

	local skills = casterSkills[caster]
	if not skills then
		debugLog("REJECTED: No skills found for caster")
		warn(`No skills found for caster {caster}`)
		return
	end

	local skill = skills[skillName]
	if not skill then
		debugLog("REJECTED: Skill not found:", skillName)
		return
	end

	local skillCfg = skill.config or SkillsConfig.skills[skillName]
	local comboCfg = skillCfg and skillCfg.combo
	debugLog("Has comboCfg:", comboCfg ~= nil)

	-- Check if entity can cast (pass combo info for chaining support)
	local canCast, reason = permissions:canCast(caster, {
		skillName = skillName,
		isCombo = comboCfg ~= nil,
	})
	if not canCast then
		debugLog("REJECTED: canCast failed, reason:", reason)
		return
	end

	-- Block if main skill cooldown active (cooldown gating between full uses)
	local onCD = CooldownService.isOnCooldown(caster, skillName)
	if onCD then
		debugLog("REJECTED: on_cooldown")
		return
	end

	-- Block based on execution lock via SessionManager
	-- If there's an active session for a DIFFERENT skill -> block
	-- If there's an active session for the SAME skill and it's a combo -> allow (combo chaining)
	local activeSession = SessionManager.getActive(caster)
	local isLocked = activeSession and activeSession.state ~= "COMPLETED" and activeSession.state ~= "CANCELLED"
	local lockedSkill = isLocked and activeSession.skillId or nil
	
	debugLog("SessionLock: locked=", isLocked, "lockedSkill=", lockedSkill or "nil")
	
	if isLocked then
		if lockedSkill ~= skillName then
			debugLog("REJECTED: locked by different skill")
			return -- different skill executing
		end
		-- Same skill locked
		if not comboCfg then
			debugLog("REJECTED: same skill locked but not a combo")
			return -- non-combo skill cannot be re-used during its own execution
		end
		debugLog("Same skill locked, but is combo - allowing through")
	end

	if comboCfg then
		-- Phase 3: Create session BEFORE calling skill:use()
		-- For combos, session creation happens on first step
		local session = SessionManager.getActive(caster)
		if session and (session.state == "COMPLETED" or session.state == "CANCELLED") then
			session = nil
		end

		local isNewChain = false
		if not session or session.skillId ~= skillName then
			-- New combo chain - create session
			local sessionConfig = {
				maxDuration = 10, -- TODO: Calculate from skill config
				combo = {
					steps = comboCfg.steps,
					window = comboCfg.window,
				},
			}
			session = SessionManager.create(skillName, caster, sessionConfig)
			isNewChain = true
			debugPhase3("Created NEW session for combo:", session.id:sub(1, 8))
		else
			debugPhase3("Reusing existing session for combo:", session.id:sub(1, 8))
		end

		local req = requestData or {}
		local comboState = session and session.combo or nil
		local currentStep = comboState and comboState.currentStep or 1
		local totalSteps = comboCfg.steps
		local shouldAdvance = not isNewChain and currentStep < totalSteps
		local stepToPlay = currentStep

		-- Prevent overflow beyond total steps
		if currentStep >= totalSteps and not isNewChain then
			debugLog("REJECTED: combo already at final step")
			return
		end

		if shouldAdvance then
			local advanced = SessionManager.advanceCombo(session.id)
			if not advanced then
				debugLog("REJECTED: combo advance blocked")
				SessionManager.cancel(session.id, "combo_advance_failed")
				return
			end
			stepToPlay = session.combo and session.combo.currentStep or (currentStep + 1)
		else
			stepToPlay = currentStep
		end

		local stepToken = session and session.combo and session.combo.stepToken or nil

		req.combo = {
			step = stepToPlay,
			total = comboCfg.steps,
			window = comboCfg.window,
			isNewChain = isNewChain,
			finalCd = comboCfg.comboCooldown or skill.cooldown,
			token = stepToken,
		}
		-- Phase 3: Pass session ID to skill
		req.sessionId = session and session.id or nil

		-- Pass through attemptId if provided
		if requestData and requestData.attemptId then
			req.attemptId = requestData.attemptId
		end
		local skillData = skill:use(req)
		if not skillData then
			return
		end
		local response = {
			duration = skillData and skillData.duration,
			step = stepToPlay,
			total = comboCfg.steps,
			window = comboCfg.window,
			attemptId = requestData and requestData.attemptId or nil,
			sessionId = session and session.id or nil, -- Phase 3: Include session ID in response
		}
		return response
	else
		-- Phase 3: Create session for non-combo skills
		local sessionConfig = {
			maxDuration = 10, -- TODO: Calculate from skill config
			combo = nil,
		}
		local session = SessionManager.create(skillName, caster, sessionConfig)
		debugPhase3("Created session for non-combo skill:", session.id:sub(1, 8))
		
		-- Pass session ID to skill
		local req = requestData or {}
		req.sessionId = session.id
		
		-- Non-combo: just execute
		local result = skill:use(req)
		
		-- Include sessionId in response
		if result then
			result.sessionId = session.id
		else
			result = { sessionId = session.id }
		end
		
		-- Include attemptId in response if provided
		if requestData and requestData.attemptId then
			result.attemptId = requestData.attemptId
		end
		return result
	end
end

-- Assign to local alias after definition
useSkill = SkillsManager.useSkill

function SkillsManager.removeAll(caster: Caster)
	local skills = casterSkills[caster]
	if not skills then
		return
	end
	casterSkills[caster] = nil

	sendDelta(caster, "all_skills_removed")
	-- TODO: Consider calling cleanup hooks on skill instances if needed
end

function SkillsManager.removeSkill(caster: Caster, skillName: string)
	local skills = casterSkills[caster]
	if not skills then
		return
	end
	skills[skillName] = nil

	sendDelta(caster, "skill_removed", {
		skillName = skillName,
	})
end

function SkillsManager.getSkill(caster: Caster, skillName: string)
	local skills = casterSkills[caster]
	if not skills then
		return nil
	end
	return skills[skillName]
end

function SkillsManager.getSkillConfig(caster: Caster, skillName: string)
	local skill = SkillsManager.getSkill(caster, skillName)
	if skill and skill.config then
		return skill.config
	end
	return nil
end

dispatcherAny:onRequest("SkillsRequest", function(requestData, _meta, context)
	local player = context.player
	if not player then
		return { success = false, error = "no_player" }
	end
	if not requestData or requestData.action ~= "use" then
		return { success = false, error = "invalid_action" }
	end

	local skillName = requestData.skillName
	if type(skillName) ~= "string" then
		return { success = false, error = "invalid_skill" }
	end

	local playerId = Registrar.getPlayerId(player)

	useSkill(playerId, skillName, requestData)
	return { success = true }
end)

dispatcher:onRequest("SkillRequestUse", function(requestData, _meta, context)
	print("Received: ", requestData)
	local player = context.player
	if not player then
		return { success = false, error = "no_player" }
	end
	local skillName = requestData.skillName
	local playerId = Registrar.getPlayerId(player)
	local result, reason = SkillsManager.canUse(playerId, skillName)
	if not result then
		return { success = false, error = reason }
	end
	local data = SkillsManager.useSkill(playerId, skillName, requestData)
	if data then
		return { success = true, data = data }
	end
	-- useSkill returned nil - blocked by cooldown/execution/combo window
	return { success = false, error = "blocked" }
end)

return SkillsManager
