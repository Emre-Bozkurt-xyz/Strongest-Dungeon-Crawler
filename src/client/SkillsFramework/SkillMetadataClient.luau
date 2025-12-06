--!strict
-- SkillMetadataClient: Extensible cache for server-computed skill metadata
-- Receives costs, damage estimates, conversions, and other skill data from server
-- Used by BaseSkill for accurate pre-flight checks and by UI for tooltips/displays
-- Design: Server calculates with full observer/mediator pipeline, sends hints to client

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Networking = require(ReplicatedStorage.Shared.Networking)

local EVENT_NAME = "SkillMetadataUpdate"
local REQUEST_SNAPSHOT = "SkillMetadataSnapshot"
local SKILLS_CHANNEL_NAME = "Skills"

local dispatcher = Networking.client()
local dispatcherAny = dispatcher :: any
dispatcherAny:_ensureChannel(SKILLS_CHANNEL_NAME)

local SkillMetadataClient = {}

-- Extensible metadata type - can add new fields for damage, conversions, etc.
export type SkillMetadata = {
	-- Resource costs (required for pre-flight checks)
	cost: number?, -- Final calculated cost after all modifiers
	costResource: string?, -- Which resource to consume ("Mana", "Stamina", "Health", etc.)
	comboCosts: { number }?, -- Per-step costs for combo skills
	
	-- Combo timing (required for window calculation)
	combo: {
		steps: number,
		window: number,
		stepDelays: { number }?,
		hitDelays: { number }?,
		recovery: number?,
		stepDurations: { number }?,
		comboCooldown: number?,
	}?,
	
	-- Damage/output estimates (optional, for tooltips)
	estimatedDamage: number?, -- Estimated damage output with current stats
	damageBreakdown: { [string]: number }?, -- Damage by type (Physical, Magical, Fire, etc.)
	
	-- Additional metadata (extensible)
	customData: { [string]: any }?, -- Arbitrary key-value pairs for future additions
}

-- Cache of skill metadata by skill name
local metadataCache: { [string]: SkillMetadata } = {}

local listeners: { (string, SkillMetadata) -> () } = {}

local function fire(skillName: string, metadata: SkillMetadata)
	for _, cb in ipairs(listeners) do
		pcall(cb, skillName, metadata)
	end
end

-- Get full metadata for a skill
function SkillMetadataClient.get(skillName: string): SkillMetadata?
	return metadataCache[skillName]
end

-- Get estimated cost for a skill (with optional step for combos)
function SkillMetadataClient.getCost(skillName: string, step: number?): number?
	local metadata = metadataCache[skillName]
	if not metadata then
		return nil
	end
	
	-- For combo skills, try to get per-step cost
	if step and metadata.comboCosts then
		return metadata.comboCosts[step]
	end
	
	-- Fall back to base cost
	return metadata.cost
end

-- Get which resource a skill will consume
function SkillMetadataClient.getCostResource(skillName: string): string?
	local metadata = metadataCache[skillName]
	if not metadata then
		return nil
	end
	return metadata.costResource
end

-- Get estimated damage output for a skill
function SkillMetadataClient.getEstimatedDamage(skillName: string): number?
	local metadata = metadataCache[skillName]
	if not metadata then
		return nil
	end
	return metadata.estimatedDamage
end

-- Get damage breakdown by type (for tooltip displays)
function SkillMetadataClient.getDamageBreakdown(skillName: string): { [string]: number }?
	local metadata = metadataCache[skillName]
	if not metadata then
		return nil
	end
	return metadata.damageBreakdown
end

-- Check if we have metadata cached for a skill
function SkillMetadataClient.hasMetadata(skillName: string): boolean
	return metadataCache[skillName] ~= nil
end

-- Listen to metadata changes (useful for UI updates)
function SkillMetadataClient.onChanged(callback: (string, SkillMetadata) -> ()): () -> ()
	table.insert(listeners, callback)
	return function()
		for i, cb in ipairs(listeners) do
			if cb == callback then
				table.remove(listeners, i)
				break
			end
		end
	end
end

-- Clear all cached metadata (e.g., on character respawn)
function SkillMetadataClient.clear()
	table.clear(metadataCache)
end

-- Request full snapshot from server (e.g., on initial load)
function SkillMetadataClient.requestSnapshot()
	local ok, snapshot = pcall(function()
		return dispatcherAny:request(REQUEST_SNAPSHOT, {})
	end)
	
	if not ok then
		warn("📋 [CLIENT-METADATA] Failed to request snapshot:", snapshot)
		return
	end
	
	if type(snapshot) ~= "table" then
		warn("📋 [CLIENT-METADATA] Invalid snapshot received:", typeof(snapshot))
		return
	end
	
	for skillName, metadata in pairs(snapshot) do
		if type(skillName) == "string" and type(metadata) == "table" then
			metadataCache[skillName] = metadata
		end
	end
end

-- Internal: Update cache from server event
local function updateMetadata(skillName: string, metadata: SkillMetadata)
	metadataCache[skillName] = metadata
	fire(skillName, metadata)
end

-- Listen to server metadata updates
dispatcherAny:on(EVENT_NAME, function(payload: any, _meta: any?)
	if type(payload) ~= "table" then
		return
	end
	
	local skillName = payload.skillName
	local metadata = payload.metadata
	
	if type(skillName) == "string" and type(metadata) == "table" then
		updateMetadata(skillName, metadata)
	end
end)

return SkillMetadataClient
