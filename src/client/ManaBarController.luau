local TS = game:GetService("TweenService")

local ManaBarController = {}
ManaBarController.__index = ManaBarController

function ManaBarController.new(Parent: Instance)
	local self = setmetatable({}, ManaBarController)

	-- Initialize mana bar UI elements
	self.manaBar = Parent:WaitForChild("ManaBar")
	self.fillBar = self.manaBar:WaitForChild("ProgressBar"):WaitForChild("FillPanel")
	self.manaLabel = self.manaBar:WaitForChild("ManaLabel")
	self.maxManaLabel = self.manaBar:WaitForChild("MaxManaLabel")

	return self
end

function ManaBarController:handleManaChanged(mana, maxMana)
	mana = math.clamp(mana, 0, maxMana)
	local fillAmount = mana / maxMana

	-- Update the fill bar size based on mana percentage
	TS:Create(
		self.fillBar,
		TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.new(fillAmount, 0, 1, 0) }
	):Play()

	-- Update mana labels
	self.manaLabel.Text = tostring(mana)
	self.maxManaLabel.Text = "/" .. tostring(maxMana)
end

return ManaBarController
