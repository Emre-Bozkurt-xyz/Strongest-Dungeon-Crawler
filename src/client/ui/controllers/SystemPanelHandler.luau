--!strict
-- Client-side system panel handler for displaying stats and attributes

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HealthBarController = require(script.Parent.HealthBarController)
local ManaBarController = require(script.Parent.ManaBarController)
local StaminaBarController = require(script.Parent.StaminaBarController)
local AttributesUIController = require(script.Parent.AttributesUIController)
local WorldGUIManager = require(script.Parent.Parent.Parent.WorldGUIManager)
local StatusPreviewController = require(script.Parent.StatusPreviewController)

local SystemPanelHandler = {}
SystemPanelHandler.__index = SystemPanelHandler

-- Import clients for centralized data access
local AttributesClient = require(script.Parent.Parent.Parent.AttributesClient)
local StatsClient = require(script.Parent.Parent.Parent.StatsClient)
local NetRay = require(ReplicatedStorage.Packages.NetRay)

function SystemPanelHandler.new()
    local self = setmetatable({}, SystemPanelHandler)

    -- Create the system panel
    self.systemPanel = ReplicatedStorage.Assets.SystemPanel:Clone()

    -- Initialize UI controllers
    self.statusPanel = self.systemPanel:FindFirstChild("StatusPanel", true)
    self.attributesPanel = self.systemPanel:FindFirstChild("AttributesPanel", true)
    self.infoPanel = self.systemPanel:FindFirstChild("InfoPanel", true)
    if self.statusPanel and self.attributesPanel then
        self.staminaBarController = StaminaBarController.new(self.statusPanel)
        self.healthBarController = HealthBarController.new(self.statusPanel)
        self.manaBarController = ManaBarController.new(self.statusPanel)
        self.attributesUIController = AttributesUIController.new(self.attributesPanel)
    end

    -- Register panel with WorldGUIManager for positioning
    local worldGUIManager = WorldGUIManager.getInstance()
    worldGUIManager:registerPanel({
        name = "SystemPanel",
        part = self.systemPanel,
        faceCamera = true,
        followMode = "camera",
        offset = Vector3.new(0, 0.75, 0), -- lift the panel slightly to avoid player head overlap
        camSpaceOffset = Vector3.new(0, 0.0, 0.0), -- tweak if needed without affecting OS mode
    })

    -- Listen for stats updates via NetRay event
    local statsEvent = NetRay:GetEvent("StatsDelta")
    if statsEvent then
        statsEvent:OnEvent(function(_delta)
            -- Let StatsClient consume and update state first, then refresh UI
            task.defer(function()
                local statsData = StatsClient.getFormattedStats()
                if statsData then
                    self:updateStats(statsData)
                end
            end)
        end)
    end

    -- Listen for attributes updates via NetRay event
    local attributesEvent = NetRay:GetEvent("AttributesDelta")
    if attributesEvent then
        attributesEvent:OnEvent(function(_delta)
            -- Pull latest state from AttributesClient and update UI
            task.defer(function()
                local attributeData = AttributesClient.getFormattedAttributes()
                if attributeData then
                    self:updateAttributes(attributeData)
                end
            end)
        end)
    end

    -- Initial update to get current data
    local function initialUpdate()
        -- Update stats
        local statsData = StatsClient.getFormattedStats()
        if statsData then
            self:updateStats(statsData)
            -- Also update status preview
            StatusPreviewController.updateStats(statsData)
        end

        -- Update attributes
        local attributeData = AttributesClient.getFormattedAttributes()
        if attributeData then
            self:updateAttributes(attributeData)
        end
    end

    -- Do initial update after a short delay
    task.wait(0.1)
    initialUpdate()

    return self
end

function SystemPanelHandler:updateStats(newStats)
    -- Logic to update stats in the system panel
    if not self.systemPanel then
        warn("System panel not initialized")
        return
    end

    -- Defensive checks for stats objects
    if newStats.Health and newStats.Health.getCurrentValue and newStats.Health.getValue then
        self.healthBarController:updateHealth(newStats.Health:getCurrentValue(), newStats.Health:getValue())
    end

    if newStats.Mana and newStats.Mana.getCurrentValue and newStats.Mana.getValue then
        self.manaBarController:updateMana(newStats.Mana:getCurrentValue(), newStats.Mana:getValue())
    end

    if newStats.Stamina and newStats.Stamina.getCurrentValue and newStats.Stamina.getValue then
        self.staminaBarController:updateStamina(newStats.Stamina:getCurrentValue(), newStats.Stamina:getValue())
    end

    -- Mirror to status preview as well
    StatusPreviewController.updateStats(newStats)
end

function SystemPanelHandler:updateAttributes(attributes)
    -- Logic to update attributes in the system panel
    if not self.attributesUIController then
        warn("Attributes UI Controller not initialized")
        return
    end

    self.attributesUIController:updateAttributes(attributes)
end

function SystemPanelHandler:togglePanel()
    -- Toggle visibility of the system panel
    if not self.systemPanel then
        warn("System panel not initialized")
        return
    end
    local worldGUIManager = WorldGUIManager.getInstance()
    local isVisible = worldGUIManager:isPanelVisible("SystemPanel")
    if isVisible then
        self:hidePanel()
    else
        self:displayPanel()
    end
end

function SystemPanelHandler:displayPanel()
    -- WorldGUIManager handles positioning, we just need to place it in workspace
    if not self.systemPanel then
        warn("System panel not initialized")
        return
    end

    -- Use WorldGUIManager visibility controls (it will handle parenting)
    local worldGUIManager = WorldGUIManager.getInstance()
    worldGUIManager:setPanelVisibility("SystemPanel", true, 0.5, workspace)

    -- Hide status preview while system panel is shown
    worldGUIManager:setPanelVisibility("StatusPreview", false, 0.2, workspace)

    -- No focus effects; CameraController handles per-mode follow behavior
end

function SystemPanelHandler:hidePanel()
    -- Use WorldGUIManager for smooth hiding (it will handle unparenting after fade)
    local worldGUIManager = WorldGUIManager.getInstance()
    worldGUIManager:setPanelVisibility("SystemPanel", false, 0.5, workspace)

    -- Show status preview again
    worldGUIManager:setPanelVisibility("StatusPreview", true, 0.2, workspace)

    -- No focus effects on hide
end

function SystemPanelHandler:togglePreview()
    -- Temporarily hide attribute and info panels to show only status bars
    if not self.attributesPanel or not self.infoPanel then
        warn("Attributes or Info panel not initialized")
        return
    end
    local currentlyVisible = self.attributesPanel.Visible or self.infoPanel.Visible
    self.attributesPanel.Visible = not currentlyVisible
    self.infoPanel.Visible = not currentlyVisible
end

-- Lazy singleton facade so callers don't need to instantiate manually
local _instance: any
local _autoUnlockEnabled = true -- default on; can be toggled by user preferences later

local function getOrCreate()
    if _instance then
        return _instance
    end
    _instance = SystemPanelHandler.new()
    return _instance
end

return {
    -- expose class constructor just in case
    new = SystemPanelHandler.new,
    get = getOrCreate,
    -- preference flag API
    isAutoUnlockEnabled = function(): boolean
        return _autoUnlockEnabled
    end,
    setAutoUnlockEnabled = function(v: boolean)
        _autoUnlockEnabled = v and true or false
    end,
    show = function()
        local inst = getOrCreate()
        inst:displayPanel()
        if _autoUnlockEnabled then
            -- Auto-unlock cursor for OS interaction
            local CameraController = require(script.Parent.Parent.Parent.CameraController)
            CameraController.getInstance():setCursorUnlocked(true)
        end
    end,
    hide = function()
        local inst = getOrCreate()
        inst:hidePanel()
        if _autoUnlockEnabled then
            -- Re-lock cursor when panel hides (in OS mode this resumes look)
            local CameraController = require(script.Parent.Parent.Parent.CameraController)
            CameraController.getInstance():setCursorUnlocked(false)
        end
    end,
    toggle = function()
        local inst = getOrCreate()
        local worldGUIManager = WorldGUIManager.getInstance()
        local visible = worldGUIManager:isPanelVisible("SystemPanel")
        inst:togglePanel()
    local CameraController = require(script.Parent.Parent.Parent.CameraController)
        -- After toggling, query new state to decide lock/unlock
        local nowVisible = worldGUIManager:isPanelVisible("SystemPanel")
        if _autoUnlockEnabled then
            if nowVisible and not visible then
                CameraController.getInstance():setCursorUnlocked(true)
            elseif (not nowVisible) and visible then
                CameraController.getInstance():setCursorUnlocked(false)
            end
        end
    end,
    updateStats = function(s)
        getOrCreate():updateStats(s)
    end,
    updateAttributes = function(a)
        getOrCreate():updateAttributes(a)
    end,
}
