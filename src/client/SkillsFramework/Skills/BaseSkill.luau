local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Networking = require(ReplicatedStorage.Shared.Networking)
local Players = game:GetService("Players")

local FXPlayer = require(script.Parent.Parent.Parent.fx.FXPlayer)
local AnimationCoordinator = require(script.Parent.Parent.Parent.Animation.AnimationCoordinator)
local ClientSpec = require(ReplicatedStorage.Shared.skills.ClientSpec)
local Replicator = require(script.Parent.Parent.Parent.fx.Replicator)

local dispatcher = Networking.client()
dispatcher:_ensureChannel("Skills")

local BaseSkill = {}
BaseSkill.__index = BaseSkill

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

	return self
end

function BaseSkill:use() end

function BaseSkill:_findAnchor(anchorName: string): Instance?
	local char = self.player.Character
	if not char then
		return nil
	end
	local anchor = char:FindFirstChild(anchorName, true)
	return anchor
end

function BaseSkill:playAnimation(animKey: string, opts: { [string]: any }?): AnimationTrack?
	local animHandler = self.animationCoordinator:playSkillAnimation(self.name, animKey, opts)

	-- Bind marker events from config
	if self.config.markers then
		for markerName, val in pairs(self.config.markers) do
			local anchorName = self.config.fx.anchor or "HumanoidRootPart"

			if self.config.anchorsByStep and opts and opts.step then
				anchorName = self.config.anchorsByStep[opts.step] or anchorName
			end

			local anchor = self:_findAnchor(anchorName)
			self:bindMarkerEvent(markerName, function(_ctx: any)
				if type(val) == "string" then
					self.fxPlayer:playAttached(val, anchor)
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

						local handler = self.fxPlayer:spawnAttached(val.key, anchor, val.offset)

						self.fxMap[val.key] = handler

						Replicator.emitFX({
							entityId = self.entityId,
							fxKey = val.key,
							anchorName = anchorName,
							action = "start",
						})
					elseif val.action == "stop" then
						if self.fxMap[val.key] then
							pcall(self.fxMap[val.key].Stop)
							self.fxMap[val.key] = nil
						end
					else
						self.fxPlayer:playAttached(val.key, anchor, val.offset, val.lifetime)

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

	return animHandler and animHandler:getTrack() or nil
end

function BaseSkill:bindMarkerEvent(markerName: string, callback: (ctx: any) -> ())
	self.animationCoordinator:onSkillMarker(self.name, markerName, callback)
end

function BaseSkill:requestUse(): any
	local response = dispatcher:request("SkillRequestUse", {
		skillName = self.config.name,
		userId = self.player.UserId,
	})
	return response
end

return BaseSkill
