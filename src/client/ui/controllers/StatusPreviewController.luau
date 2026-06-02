--!strict
-- StatusPreviewController: Character-anchored status preview using a BasePart + SurfaceGui

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldGUIManager = require(script.Parent.Parent.Parent.WorldGUIManager)
local HealthBarController = require(script.Parent.HealthBarController)
local ManaBarController = require(script.Parent.ManaBarController)
local StaminaBarController = require(script.Parent.StaminaBarController)
local PanelTemplateResolver = require(script.Parent.Parent.runtime.PanelTemplateResolver)
local PanelBinder = require(script.Parent.Parent.runtime.PanelBinder)
local SharedConfig = require(ReplicatedStorage.Shared.Config)
local DevTuningService = require(script.Parent.Parent.Parent.dev.DevTuningService)
local StatsClient = require(script.Parent.Parent.Parent.StatsClient)

local StatusPreviewController = {}
StatusPreviewController.__index = StatusPreviewController

local WorldGUIConfig = SharedConfig.WorldGUI
local STATUS_PREVIEW_CONFIG = WorldGUIConfig.panels.StatusPreview

local function tunedVector3(path: string, fallback: Vector3): Vector3
	local value = DevTuningService.get(path)
	return if typeof(value) == "Vector3" then value else fallback
end

local function resolveTemplate(name: string): BasePart
	local template = PanelTemplateResolver.resolveWorldPart(name)
	assert(template, `StatusPreviewController: missing template {name}`)
	return template
end

function StatusPreviewController.new()
	local self = setmetatable({}, StatusPreviewController) :: any
	self.player = Players.LocalPlayer
	self._statsDisconnect = function() end
	self._tuneDisconnect = nil
	self._config = {
		offset = tunedVector3("WorldGUI.panels.StatusPreview.offset", STATUS_PREVIEW_CONFIG.offset),
		playerSpaceOffset = tunedVector3(
			"WorldGUI.panels.StatusPreview.playerSpaceOffset",
			STATUS_PREVIEW_CONFIG.playerSpaceOffset
		),
	}

	self.panelPart = resolveTemplate("StatusPreviewPanel"):Clone()
	self.panelPart.Parent = workspace
	local binder = PanelBinder.new(self.panelPart)
	local statusPanel = binder:require({ "StatusPanel" }, "Frame", "StatusPreviewPanel.StatusPanel")

	self.healthBarController = HealthBarController.new(statusPanel)
	self.manaBarController = ManaBarController.new(statusPanel)
	self.staminaBarController = StaminaBarController.new(statusPanel)

	local wgm = WorldGUIManager.getInstance()
	wgm:registerPanel({
		name = "StatusPreview",
		part = self.panelPart,
		faceCamera = true,
		followMode = "player",
		offset = self._config.offset,
		playerSpaceOffset = self._config.playerSpaceOffset,
	})

	self._tuneDisconnect = DevTuningService.subscribe("WorldGUI.panels.StatusPreview", function()
		self._config.offset = tunedVector3("WorldGUI.panels.StatusPreview.offset", STATUS_PREVIEW_CONFIG.offset)
		self._config.playerSpaceOffset =
			tunedVector3("WorldGUI.panels.StatusPreview.playerSpaceOffset", STATUS_PREVIEW_CONFIG.playerSpaceOffset)
		wgm:updatePanel("StatusPreview", {
			offset = self._config.offset,
			playerSpaceOffset = self._config.playerSpaceOffset,
		})
	end)

	task.defer(function()
		local stats = StatsClient.getFormattedStats()
		if stats then
			self:updateStats(stats)
		end
	end)

	wgm:setPanelVisibility("StatusPreview", true, 0.2, workspace)

	self._statsDisconnect = StatsClient.onChanged(function()
		task.defer(function()
			local stats = StatsClient.getFormattedStats()
			if stats then
				self:updateStats(stats)
			end
		end)
	end)

	return self
end

function StatusPreviewController:updateStats(newStats)
	if newStats.Health and newStats.Health.getCurrentValue and newStats.Health.getValue then
		self.healthBarController:updateHealth(newStats.Health:getCurrentValue(), newStats.Health:getValue())
	end
	if newStats.Mana and newStats.Mana.getCurrentValue and newStats.Mana.getValue then
		self.manaBarController:updateMana(newStats.Mana:getCurrentValue(), newStats.Mana:getValue())
	end
	if newStats.Stamina and newStats.Stamina.getCurrentValue and newStats.Stamina.getValue then
		self.staminaBarController:updateStamina(newStats.Stamina:getCurrentValue(), newStats.Stamina:getValue())
	end
end

function StatusPreviewController:destroy()
	if self.panelPart then
		self.panelPart:Destroy()
	end
	if self._tuneDisconnect then
		self._tuneDisconnect()
		self._tuneDisconnect = nil
	end
	self._statsDisconnect()
	self._statsDisconnect = function() end
end

local _inst: any

local function get()
	if _inst then
		return _inst
	end
	_inst = StatusPreviewController.new()
	return _inst
end

return {
	new = StatusPreviewController.new,
	get = get,
	updateStats = function(s)
		get():updateStats(s)
	end,
}
