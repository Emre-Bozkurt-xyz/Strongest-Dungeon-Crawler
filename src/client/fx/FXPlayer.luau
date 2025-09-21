--!strict
-- FX registry: plays particle/sound FX by key with simple pooling

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FXPlayer = {}

local FXFolder = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("FX")

local DEFAULT_LIFETIME = 1 -- seconds

local function primeFX(fx: Instance)
	for _, d in ipairs(fx:GetDescendants()) do
		if d:IsA("ParticleEmitter") then
			-- if it's a burst style, Emit once; otherwise leave Enabled
			if d.Rate <= 0 then
				d:Emit(tonumber(d:GetAttribute("EmitCount")) or 10)
			else
				d.Enabled = true
			end
		elseif d:IsA("Sound") then
			d:Play()
		end
	end
end

function FXPlayer.playAt(key: string, cframe: CFrame, lifetime: number?)
	if not FXFolder then
		return
	end
	local template = FXFolder:FindFirstChild(key)
	if not template then
		return
	end
	local fx = template:Clone()
	fx.Transparency = 1
	fx.CFrame = cframe
	fx.Parent = workspace
	primeFX(fx)
	game:GetService("Debris"):AddItem(fx, (lifetime or DEFAULT_LIFETIME))
end

function FXPlayer.playAttached(key: string, attachment: Attachment, offset: CFrame?, lifetime: number?)
	if not FXFolder then
		return
	end
	local template = FXFolder:FindFirstChild(key)
	if not template then
		return
	end
	local fx = template:Clone()
	fx.Parent = attachment
	if fx:IsA("BasePart") then
		fx.Anchored = false
	end
	primeFX(fx)
	-- For static offset adjustments on simple BaseParts/Models without bones we can reposition each Heartbeat if offset provided.
	if offset then
		local runService = game:GetService("RunService")
		local conn: RBXScriptConnection? = nil
		conn = runService.Heartbeat:Connect(function()
			if fx.Parent ~= attachment then
				if conn then conn:Disconnect() end
				return
			end
			if fx:IsA("BasePart") then
				fx.CFrame = attachment.WorldCFrame * offset
			end
		end)
	end
	game:GetService("Debris"):AddItem(fx, (lifetime or DEFAULT_LIFETIME))
end

return FXPlayer
