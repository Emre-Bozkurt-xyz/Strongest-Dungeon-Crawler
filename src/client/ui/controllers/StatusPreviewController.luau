--!strict
-- StatusPreviewController: Character-anchored status preview using a BasePart + SurfaceGui

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- no run loop needed; WorldGUIManager handles movement

local WorldGUIManager = require(script.Parent.Parent.Parent.WorldGUIManager)
local HealthBarController = require(script.Parent.HealthBarController)
local ManaBarController = require(script.Parent.ManaBarController)
local StaminaBarController = require(script.Parent.StaminaBarController)

local StatsClient = require(script.Parent.Parent.Parent.StatsClient)

local StatusPreviewController = {}
StatusPreviewController.__index = StatusPreviewController

-- Tunables
local PLAYER_SPACE_OFFSET = Vector3.new(4, 0.7, 0.1) -- right, up, forward relative to HRP

function StatusPreviewController.new()
    local self = setmetatable({}, StatusPreviewController) :: any
    self.player = Players.LocalPlayer

    -- Require a prebuilt BasePart similar to SystemPanel, e.g., ReplicatedStorage.Assets.StatusPreviewPanel
    local template = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("StatusPreviewPanel")
    assert(template and template:IsA("BasePart"), "StatusPreviewController: ReplicatedStorage.Assets.StatusPreviewPanel BasePart is required")
    self.panelPart = (template :: BasePart):Clone()
    self.panelPart.Parent = workspace
    local statusPanel = self.panelPart:FindFirstChild("StatusPanel", true)
    assert(statusPanel ~= nil, "StatusPreviewController: 'StatusPanel' Frame not found under StatusPreviewPanel")

    -- Wire existing bar controllers into the billboard content
    self.healthBarController = HealthBarController.new(statusPanel)
    self.manaBarController = ManaBarController.new(statusPanel)
    self.staminaBarController = StaminaBarController.new(statusPanel)

    -- Register with WorldGUIManager in player follow mode with a player-space offset
    local wgm = WorldGUIManager.getInstance()
    wgm:registerPanel({
        name = "StatusPreview",
        part = self.panelPart,
        faceCamera = true,
        followMode = "player",
        offset = Vector3.new(0, 0, 0),
        playerSpaceOffset = PLAYER_SPACE_OFFSET,
    })

    -- Initial populate
    task.defer(function()
        local s = StatsClient.getFormattedStats()
        if s then
            self:updateStats(s)
        end
    end)

    -- Make preview visible by default; SystemPanelHandler will hide/show as needed
    wgm:setPanelVisibility("StatusPreview", true, 0.2, workspace)

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
end

-- Lazy singleton for convenience
local _inst: any
local function get()
    if _inst then return _inst end
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
