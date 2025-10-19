local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Networking = require(ReplicatedStorage.Shared.Networking)

local dispatcher = Networking.client()
local dispatcherAny = dispatcher :: any
local ATTRIBUTES_CHANNEL_NAME = "Attributes"
dispatcherAny:_ensureChannel(ATTRIBUTES_CHANNEL_NAME)

local AttributesUIController = {}
AttributesUIController.__index = AttributesUIController

function AttributesUIController.new(Parent: Instance)
    local self = setmetatable({}, AttributesUIController)

    self.attributeButtons = {}

    -- Initialize mana bar UI elements
    self.availableAPLabel =
        Parent:WaitForChild("AvailablePointsPanel"):WaitForChild("ValuesPanel"):WaitForChild("APLabel")

    local strengthFrame = Parent:WaitForChild("StrengthPanel")
    self.strengthBaseLabel = strengthFrame:WaitForChild("ValuesPanel"):WaitForChild("BaseValueLabel")
    self.strengthBonusLabel = strengthFrame:WaitForChild("ValuesPanel"):WaitForChild("BonusValueLabel")

    self.attributeButtons.Strength = strengthFrame

    local intelligenceFrame = Parent:WaitForChild("IntelligencePanel")
    self.intelligenceBaseLabel = intelligenceFrame:WaitForChild("ValuesPanel"):WaitForChild("BaseValueLabel")
    self.intelligenceBonusLabel = intelligenceFrame:WaitForChild("ValuesPanel"):WaitForChild("BonusValueLabel")

    self.attributeButtons.Intelligence = intelligenceFrame

    local dexterityFrame = Parent:WaitForChild("DexterityPanel")
    self.dexterityBaseLabel = dexterityFrame:WaitForChild("ValuesPanel"):WaitForChild("BaseValueLabel")
    self.dexterityBonusLabel = dexterityFrame:WaitForChild("ValuesPanel"):WaitForChild("BonusValueLabel")

    self.attributeButtons.Dexterity = dexterityFrame

    local defenseFrame = Parent:WaitForChild("DefensePanel")
    self.defenseBaseLabel = defenseFrame:WaitForChild("ValuesPanel"):WaitForChild("BaseValueLabel")
    self.defenseBonusLabel = defenseFrame:WaitForChild("ValuesPanel"):WaitForChild("BonusValueLabel")

    self.attributeButtons.Defense = defenseFrame

    local perceptionFrame = Parent:WaitForChild("PerceptionPanel")
    self.perceptionBaseLabel = perceptionFrame:WaitForChild("ValuesPanel"):WaitForChild("BaseValueLabel")
    self.perceptionBonusLabel = perceptionFrame:WaitForChild("ValuesPanel"):WaitForChild("BonusValueLabel")

    self.attributeButtons.Perception = perceptionFrame

    -- Set up click listeners for each attribute button via dispatcher
    local AttributesClient = require(script.Parent.Parent.Parent.AttributesClient)

    for attributeName, frame in pairs(self.attributeButtons) do
        frame.MouseButton1Click:Connect(function()
            -- Send one spend request per click, immediately, with trace info
            local now = os.clock()
            local traceId = ("cli-%s-%.4f"):format(attributeName, now)
            task.spawn(function()
                local ok, responseOrError = pcall(function()
                    return dispatcherAny:request("AttributesSpendPoint", {
                        target = attributeName,
                        trace = { id = traceId, clientSentTs = now },
                    }, {
                        qos = "HIGH",
                    })
                end)
                if not ok then
                    warn("AttributesUIController: Failed to request spend point:", responseOrError)
                    return
                end
                local res = responseOrError
                if typeof(res) ~= "table" then
                    return
                end
                local snap = res.snapshot
                if snap then
                    snap.trace = snap.trace or { id = traceId, clientSentTs = now }
                    if AttributesClient.applySnapshot(snap) then
                        local current = AttributesClient.getCurrentData()
                        if current then
                            self:updateAttributes(current)
                        end
                    end
                end
            end)
        end)
    end

    return self
end

function AttributesUIController:updateAttributes(attributes)
    -- UI refresh; debug print removed to avoid spam/flicker
    self.availableAPLabel.Text = tostring(attributes.availableAP)

    self.strengthBaseLabel.Text = tostring(attributes.Strength.base)
    self.strengthBonusLabel.Text = if attributes.Strength.bonus > 0
        then "+(" .. tostring(attributes.Strength.bonus) .. ")"
        else ""

    self.intelligenceBaseLabel.Text = tostring(attributes.Intelligence.base)
    self.intelligenceBonusLabel.Text = if attributes.Intelligence.bonus > 0
        then "+(" .. tostring(attributes.Intelligence.bonus) .. ")"
        else ""

    self.dexterityBaseLabel.Text = tostring(attributes.Dexterity.base)
    self.dexterityBonusLabel.Text = if attributes.Dexterity.bonus > 0
        then "+(" .. tostring(attributes.Dexterity.bonus) .. ")"
        else ""

    self.defenseBaseLabel.Text = tostring(attributes.Defense.base)
    self.defenseBonusLabel.Text = if attributes.Defense.bonus > 0
        then "+(" .. tostring(attributes.Defense.bonus) .. ")"
        else ""

    self.perceptionBaseLabel.Text = tostring(attributes.Perception.base)
    self.perceptionBonusLabel.Text = if attributes.Perception.bonus > 0
        then "+(" .. tostring(attributes.Perception.bonus) .. ")"
        else ""
end

return AttributesUIController
