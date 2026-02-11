--!strict
-- Client dev-only hooks (debug logging, perf timers).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local DebugConfig = require(ReplicatedStorage.Shared.Debug.DebugConfig)
local SkillSlots = require(script.Parent.Parent.SkillsFramework.SkillSlots)

local Dev = {}

local function setupSkillProfiles()
	-- Ensure at least 2 profiles for cycling during dev.
	local p1 = SkillSlots.getActiveProfileId()
	local p2 = SkillSlots.createProfile()

	-- Profile 1: core melee + traversal
	SkillSlots.setActiveProfile(p1)
	SkillSlots.assign(1, "Punch")
	SkillSlots.assign(2, "Dash")
	SkillSlots.assign(3, "DodgeRoll")

	-- Profile 2: heavier / spell skills
	SkillSlots.setActiveProfile(p2)
	SkillSlots.assign(1, "TripleStrike")
	SkillSlots.assign(2, "ManaBall")
	SkillSlots.assign(3, "CascadingManaBalls")

	-- Return to profile 1 by default.
	SkillSlots.setActiveProfile(p1)
end

function Dev.start(ctx)
	DebugConfig.setMany({
		sessionPerf = false,
		projectiles = false,
	})

	setupSkillProfiles()
end

return Dev
