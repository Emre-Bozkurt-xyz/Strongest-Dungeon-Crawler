local AttributesUIController = {}
AttributesUIController.__index = AttributesUIController

function AttributesUIController.new(Parent: Instance)
	local self = setmetatable({}, AttributesUIController)

	-- Initialize mana bar UI elements
	self.availableAPLabel =
		Parent:WaitForChild("AvailablePointsPanel"):WaitForChild("ValuesPanel"):WaitForChild("APLabel")

	self.strengthBaseLabel =
		Parent:WaitForChild("StrengthPanel"):WaitForChild("ValuesPanel"):WaitForChild("BaseValueLabel")
	self.strengthBonusLabel =
		Parent:WaitForChild("StrengthPanel"):WaitForChild("ValuesPanel"):WaitForChild("BonusValueLabel")

	self.intelligenceBaseLabel =
		Parent:WaitForChild("IntelligencePanel"):WaitForChild("ValuesPanel"):WaitForChild("BaseValueLabel")
	self.intelligenceBonusLabel =
		Parent:WaitForChild("IntelligencePanel"):WaitForChild("ValuesPanel"):WaitForChild("BonusValueLabel")

	self.dexterityBaseLabel =
		Parent:WaitForChild("DexterityPanel"):WaitForChild("ValuesPanel"):WaitForChild("BaseValueLabel")
	self.dexterityBonusLabel =
		Parent:WaitForChild("DexterityPanel"):WaitForChild("ValuesPanel"):WaitForChild("BonusValueLabel")

	self.defenseBaseLabel =
		Parent:WaitForChild("DefensePanel"):WaitForChild("ValuesPanel"):WaitForChild("BaseValueLabel")
	self.defenseBonusLabel =
		Parent:WaitForChild("DefensePanel"):WaitForChild("ValuesPanel"):WaitForChild("BonusValueLabel")

	self.perceptionBaseLabel =
		Parent:WaitForChild("PerceptionPanel"):WaitForChild("ValuesPanel"):WaitForChild("BaseValueLabel")
	self.perceptionBonusLabel =
		Parent:WaitForChild("PerceptionPanel"):WaitForChild("ValuesPanel"):WaitForChild("BonusValueLabel")

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
