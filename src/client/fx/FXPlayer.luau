--!strict
-- FX registry: plays particle/sound FX by key with simple pooling

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FXPlayer = {}

local FXFolder = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("FX")

function FXPlayer.playAt(key: string, cframe: CFrame)
	if not FXFolder then
		return
	end
	local template = FXFolder:FindFirstChild(key)
	if not template then
		return
	end
	local fx = template:Clone()
	fx.CFrame = cframe
	fx.Parent = workspace
	-- naive: play sounds/emit particles
	for _, d in ipairs(fx:GetDescendants()) do
		if d:IsA("ParticleEmitter") then
			d:Emit(d.Rate > 0 and d.Rate or 10)
		end
		if d:IsA("Sound") then
			d:Play()
		end
	end
	game:GetService("Debris"):AddItem(fx, 5)
end

return FXPlayer
