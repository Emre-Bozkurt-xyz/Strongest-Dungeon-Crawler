local TS = game:GetService("TweenService")

local HealthBarController = {}
HealthBarController.__index = HealthBarController

function HealthBarController.new(Parent: Instance)
	local self = setmetatable({}, HealthBarController)

	-- Initialize health bar UI elements
	self.healthBar = Parent:WaitForChild("HealthBar")
	self.fillBar = self.healthBar:WaitForChild("ProgressBar"):WaitForChild("FillPanel")
	self.healthLabel = self.healthBar:WaitForChild("HealthLabel")
	self.maxHealthLabel = self.healthBar:WaitForChild("MaxHealthLabel")

	return self
end

function HealthBarController:handleHealthChanged(health, maxHealth)
	health = math.clamp(health, 0, maxHealth)
	local fillAmount = health / maxHealth

	-- Update the fill bar size based on health percentage
	TS:Create(
		self.fillBar,
		TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.new(fillAmount, 0, 1, 0) }
	):Play()

	-- Update health labels
	self.healthLabel.Text = tostring(health)
	self.maxHealthLabel.Text = "/" .. tostring(maxHealth)
end

return HealthBarController
