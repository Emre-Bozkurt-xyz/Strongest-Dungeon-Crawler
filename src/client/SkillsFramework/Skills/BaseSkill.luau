local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Networking = require(ReplicatedStorage.Shared.Networking)
local Players = game:GetService("Players")

local FXPlayer = require(script.Parent.Parent.Parent.fx.FXPlayer)
local AnimationCoordinator = require(script.Parent.Parent.Parent.Animation.AnimationCoordinator)
local ClientSpec = require(ReplicatedStorage.Shared.skills.ClientSpec)
local Replicator = require(script.Parent.Parent.Parent.fx.Replicator)

-- Client-side state mirrors
local CooldownClient = require(script.Parent.Parent.CooldownClient)
local ExecutionClient = require(script.Parent.Parent.ExecutionClient)
local SkillMetadataClient = require(script.Parent.Parent.SkillMetadataClient)
local StatsClient = require(script.Parent.Parent.Parent.StatsClient)

local dispatcher = Networking.client()
dispatcher:_ensureChannel("Skills")

local BaseSkill = {}
BaseSkill.__index = BaseSkill

-- Rejection reasons for user feedback
export type RejectionReason = 
	"on_cooldown" |
	"on_gcd" |
	"locked" |
	"insufficient_resources" |
	"invalid_combo_window" |
	"unknown"

function BaseSkill.new(name: string?, config: any?)
	local self = {}
	setmetatable(self, BaseSkill)

	self.name = name or "Skill"

	self.fxPlayer = FXPlayer
	self.animationCoordinator = AnimationCoordinator
	self.clientSpec = ClientSpec

	self.player = Players.LocalPlayer
	self.entityId = self.player.Character and self.player.Character:GetAttribute("EntityId")

	self.config = config or {}
	self.fxMap = {} :: { [string]: any }
	self.markerEventListenerDestroyers = {}

	return self
end

function BaseSkill:use() 
	warn("use() must not be called on base class directly")
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
	for _, destroyer in pairs(self.markerEventListenerDestroyers) do
		destroyer()
	end

	-- Bind marker events from config
	local fxConfig = self.config.fx
	local markers = fxConfig and fxConfig.markers
	if markers then
		for markerName, val in pairs(markers) do
			local anchorName = (fxConfig and fxConfig.anchor and fxConfig.anchor.name) or "HumanoidRootPart"

			if fxConfig and fxConfig.anchorsByStep and opts and opts.step then
				local stepAnchor = fxConfig.anchorsByStep[opts.step]
				anchorName = (stepAnchor and stepAnchor.name) or anchorName
			end

			local anchor = self:_findAnchor(anchorName)
			self.markerEventListenerDestroyers[markerName] = self:bindMarkerEvent(markerName, function(_ctx: any)
				if type(val) == "string" then
					self.fxPlayer.playAttached(val, anchor)
					Replicator.emitFX({
						entityId = self.entityId,
						fxKey = val,
						anchorName = anchorName,
					})
				elseif type(val) == "table" then
					if val.action == "start" then
						if self.fxMap[val.key] then
							pcall(self.fxMap[val.key].Stop)
							self.fxMap[val.key] = nil
						end

						local handler = self.fxPlayer.spawnAttached(val.key, anchor, val.offset)

						self.fxMap[val.key] = handler

						Replicator.emitFX({
							entityId = self.entityId,
							fxKey = val.key,
							anchorName = anchorName,
							action = "start",
						})
					elseif val.action == "stop" then
						if self.fxMap[val.key] then
							print("Stopping FX:", val.key)
							pcall(self.fxMap[val.key].Stop)
							self.fxMap[val.key] = nil
						end
					else
						self.fxPlayer.playAttached(val.key, anchor, val.offset, val.lifetime)

						Replicator.emitFX({
							entityId = self.entityId,
							fxKey = val.key,
							anchorName = anchorName,
							lifetime = val.lifetime,
						})
					end
				end
			end)
		end
	end

	-- NOW play the animation after all marker handlers are registered
	local animHandler = self.animationCoordinator.playSkillAnimation(self.name, animKey, opts)
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
	-- Check execution lock
	if ExecutionClient.isLocked() then
		local lockedSkill = ExecutionClient.getLockedSkill()
		-- Only allow same skill to re-enter if it's a combo advancing
		if lockedSkill ~= self.name or not isComboAdvance then
			return false, "locked"
		end
	end
	
	-- Check cooldown
	local cooldownRemaining = CooldownClient.getRemaining(self.name)
	if cooldownRemaining > 0 then
		return false, "on_cooldown"
	end
	
	-- Check global cooldown (GCD)
	local gcdRemaining = CooldownClient.getRemaining("__gcd")
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
	local cost = SkillMetadataClient.getCost(self.name, comboStep)
	local resource = SkillMetadataClient.getCostResource(self.name)
	
	-- If no metadata cached yet, warn and block (safer than allowing)
	if not cost or not resource then
		warn(`[{self.name}] No skill metadata cached yet - blocking until metadata loads`)
		return false, { cost = 0, resource = "unknown" }
	end
	
	-- No cost, always allow
	if cost <= 0 then
		return true, { cost = cost, resource = resource }
	end
	
	-- Check pool current vs cost
	local currentPool = StatsClient.getPoolCurrent(resource)
	if not currentPool then
		-- Pool not found - debug what stats are available
		local stats = StatsClient.getCurrentStats()
		warn(`[{self.name}] Pool not found for resource: {resource}`)
		if stats then
			warn(`[{self.name}] Available stats keys:`)
			for k, v in pairs(stats :: any) do
				local valType = type(v)
				if valType == "table" then
					if v.current ~= nil then
						warn(`  {k}: pool (current={v.current}, max={v.max or "?"})`)
					else
						local keys = {}
						for vk, _ in pairs(v) do
							table.insert(keys, vk)
						end
						warn(`  {k}: table with keys: [{table.concat(keys, ", ")}]`)
					end
				else
					warn(`  {k}: {valType}`)
				end
			end
		else
			warn(`[{self.name}] No stats available yet`)
		end
		return false, { cost = cost, resource = resource }
	end
	
	local hasEnough = currentPool >= cost
	return hasEnough, { cost = cost, resource = resource }
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
	
	local skillTags = self.config and (self.config.tags or self.config.categories) or nil
	
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
	local baseDuration = self.config.baseDuration
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
function BaseSkill:requestUse(): any
	local response = dispatcher:request("SkillRequestUse", {
		skillName = self.name,
		userId = self.player.UserId,
	})
	return response
end

-- Request skill use from server (non-blocking with callbacks)
-- onConfirm: Called when server confirms skill use with response data
-- onReject: Called when server rejects skill use with error reason
function BaseSkill:requestUseAsync(
	onConfirm: ((data: any) -> ())?,
	onReject: ((reason: string) -> ())?
)
	task.spawn(function()
		local response = self:requestUse()
		
		-- Handle nil response (server error or timeout)
		if not response then
			if onReject then
				onReject("server_error")
			end
			return
		end
		
		if response.success then
			if onConfirm then
				onConfirm(response.data or {})
			end
		else
			if onReject then
				onReject(response.error or "unknown")
			end
		end
	end)
end

return BaseSkill
