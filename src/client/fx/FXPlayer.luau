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

local function computeMaxParticleLifetime(inst: Instance): number
	local maxLife = 0
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("ParticleEmitter") then
			-- Stop further emission for continuous emitters
			if d.Rate > 0 then
				d.Enabled = false
			end
			local lr = d.Lifetime
			local thisLife = (typeof(lr) == "NumberRange") and (lr.Max :: number) or 0
			if thisLife > maxLife then
				maxLife = thisLife
			end
		end
	end
	-- Safety clamp to avoid extreme waits if assets are misconfigured
	if maxLife > 3 then
		maxLife = 3
	end
	return maxLife
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

-- Plays FX on a specific BasePart (no attachment required). Non-part FX will be parented under the part.

function FXPlayer.playAttached(key: string, targetAttachment: Attachment, offset: CFrame?, lifetime: number?)
	if not FXFolder then
		return
	end
	local template = FXFolder:FindFirstChild(key)
	if not template then
		return
	end

	local life = (lifetime or DEFAULT_LIFETIME)
	local offsetCf = offset or CFrame.new()
	local Debris = game:GetService("Debris")
	local RunService = game:GetService("RunService")

	local fx = template:Clone()

	if fx:IsA("BasePart") then
		fx.Anchored = true
		fx.CanCollide = false
		fx.CFrame = targetAttachment.WorldCFrame * offsetCf
		fx.Parent = workspace
		primeFX(fx)
		local conn: RBXScriptConnection? = nil
		conn = RunService.Heartbeat:Connect(function()
			if not fx.Parent or not targetAttachment.Parent then
				if conn then
					conn:Disconnect()
				end
				return
			end
			fx.CFrame = targetAttachment.WorldCFrame * offsetCf
		end)
		Debris:AddItem(fx, life)
		return
	elseif fx:IsA("Model") then
		fx.Parent = workspace
		local primary = fx.PrimaryPart
		if primary then
			primary.Anchored = true
		end
		fx:PivotTo(targetAttachment.WorldCFrame * offsetCf)
		primeFX(fx)
		local conn: RBXScriptConnection? = nil
		conn = RunService.Heartbeat:Connect(function()
			if not fx.Parent or not targetAttachment.Parent then
				if conn then
					conn:Disconnect()
				end
				return
			end
			fx:PivotTo(targetAttachment.WorldCFrame * offsetCf)
		end)
		Debris:AddItem(fx, life)
		return
	else
		-- For non-part assets (e.g., Folder with emitters/sounds), parent under attachment so they follow
		fx.Parent = targetAttachment
		primeFX(fx)
		Debris:AddItem(fx, life)
		return
	end
end

-- FX handle support for looped/long-lived effects
export type FXHandle = {
	Instance: Instance,
	Stop: () -> (),
}

-- Spawns an FX attached to an attachment and returns a handle for manual stopping.
function FXPlayer.spawnAttached(key: string, targetAttachment: Attachment, offset: CFrame?): FXHandle?
	if not FXFolder then
		return nil
	end
	local template = FXFolder:FindFirstChild(key)
	if not template then
		return nil
	end

	local offsetCf = offset or CFrame.new()
	local RunService = game:GetService("RunService")

	local fx = template:Clone()
	local conn: RBXScriptConnection? = nil

	local function cleanup()
		if fx then
			-- Disable new particles and keep following until cleanup
			local linger = computeMaxParticleLifetime(fx)
			if linger > 0 then
				game:GetService("Debris"):AddItem(fx, linger + 0.1)
			else
				fx:Destroy()
			end
		end
	end

	if fx:IsA("BasePart") then
		fx.Anchored = true
		fx.CanCollide = false
		fx.CFrame = targetAttachment.WorldCFrame * offsetCf
		fx.Parent = workspace
		primeFX(fx)
		conn = RunService.RenderStepped:Connect(function()
			if not fx or not fx.Parent then
				if conn then
					conn:Disconnect()
				end
				return
			end
			fx.CFrame = targetAttachment.WorldCFrame * offsetCf
		end)
	elseif fx:IsA("Model") then
		fx.Parent = workspace
		fx:PivotTo(targetAttachment.WorldCFrame * offsetCf)
		local primary = fx.PrimaryPart
		if primary then
			primary.Anchored = true
		end
		primeFX(fx)
		conn = RunService.RenderStepped:Connect(function()
			if not fx or not fx.Parent then
				if conn then
					conn:Disconnect()
				end
				return
			end
			(fx :: Model):PivotTo(targetAttachment.WorldCFrame * offsetCf)
		end)
	else
		-- Non-part assets (emitters/sounds) parented under attachment
		fx.Parent = targetAttachment
		primeFX(fx)
	end

	return {
		Instance = fx,
		Stop = cleanup,
	}
end

-- Spawns an FX at a fixed CFrame and returns a handle for manual stopping
function FXPlayer.spawnAt(key: string, cframe: CFrame): FXHandle?
	if not FXFolder then
		return nil
	end
	local template = FXFolder:FindFirstChild(key)
	if not template then
		return nil
	end
	local fx = template:Clone()
	fx.Parent = workspace
	if fx:IsA("BasePart") then
		fx.Anchored = true
		fx.CanCollide = false
		fx.CFrame = cframe
	elseif fx:IsA("Model") then
		(fx :: Model):PivotTo(cframe)
	end
	primeFX(fx)
	return {
		Instance = fx,
		Stop = function()
			local linger = computeMaxParticleLifetime(fx)
			if linger > 0 then
				game:GetService("Debris"):AddItem(fx, linger + 0.1)
			else
				fx:Destroy()
			end
		end,
	}
end

-- Spawns an FX on a BasePart and returns a handle. BasePart/Model will follow the part's CFrame; non-part will be parented under the part.

return FXPlayer
