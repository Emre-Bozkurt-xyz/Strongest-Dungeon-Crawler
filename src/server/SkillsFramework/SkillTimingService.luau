--!strict
-- Server-side timing resolver wrapper
-- Uses shared SkillTimingResolver with server's authoritative StatsManager

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Server = game:GetService("ServerScriptService").Server

local StatsManager = require(Server.Stats.StatsManager)
local SkillsConfig = require(script.Parent.SkillsConfig)
local SkillTimingResolver = require(ReplicatedStorage.Shared.skills.SkillTimingResolver)
local CombatLoadoutService = require(Server.Inventory.CombatLoadout.CombatLoadoutService)

local SkillTimingService = {}

function SkillTimingService.resolve(entityId: string, skillId: string)
	assert(entityId and skillId and type(skillId) == "string", "SkillTimingService.resolve: bad args")
	local skillConfig = SkillsConfig.skills[skillId]

	local skillTags = skillConfig and (skillConfig.tags or skillConfig.categories) or nil

	-- Create stat lookup function for this entity
	local function statLookup(statType: any): number?
		return StatsManager.getStatValue(entityId, statType)
	end

	-- Weapon tempo comes from the main-hand weapon in the current combat loadout (D3: tempo
	-- composes multiplicatively, the weapon sets the base). Dual-wield/secondary-hand tempo is a
	-- Phase C concern.
	local loadout = CombatLoadoutService.get(entityId)
	local weaponTempo = loadout and loadout.main and loadout.main.attackSpeed or nil

	-- Use shared resolver
	local result = SkillTimingResolver.resolve(skillTags, statLookup, weaponTempo)

	-- Return in legacy format for compatibility (can be updated later)
	return {
		durationScale = result.durationScale,
		tempo = result.tempo,
		statType = result.statType,
	}
end

return SkillTimingService
