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

	-- Set up click listeners for each attribute button
	for attributeName, frame in pairs(self.attributeButtons) do
		frame.MouseButton1Click:Connect(function()
			print("Clicked on " .. attributeName)

			-- Send delta to server to increase this attribute
			local ClientNetworkManager = require(script.Parent.ClientNetworkManager)
			local Players = game:GetService("Players")

			local delta = {
				system = "attributes",
				type = "increase_attribute",
				target = attributeName,
				timestamp = os.time(),
				data = {
					playerId = Players.LocalPlayer.UserId,
				},
			}

			ClientNetworkManager.sendDelta(delta)
		end)
	end

	return self
end

function AttributesUIController:updateAttributes(attributes)
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
