--!strict
-- MovementDirectionProvider: resolves intended movement direction and buckets.

local Players = game:GetService("Players")

local MovementDirectionProvider = {}

local function getCharacter(): Model?
	local player = Players.LocalPlayer
	return player and player.Character or nil
end

local function getRootPart(char: Model?): BasePart?
	if not char then
		return nil
	end
	return char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function getHumanoid(char: Model?): Humanoid?
	if not char then
		return nil
	end
	return char:FindFirstChildOfClass("Humanoid")
end

function MovementDirectionProvider.getMoveDirection(): Vector3
	local char = getCharacter()
	local humanoid = getHumanoid(char)
	local moveDir = humanoid and humanoid.MoveDirection or Vector3.zero
	if moveDir.Magnitude > 1e-4 then
		return moveDir.Unit
	end
	local rootPart = getRootPart(char)
	if rootPart then
		return rootPart.CFrame.LookVector
	end
	return Vector3.new(0, 0, -1)
end

function MovementDirectionProvider.getReferenceCFrame(): CFrame?
	local char = getCharacter()
	local rootPart = getRootPart(char)
	return rootPart and rootPart.CFrame or nil
end

function MovementDirectionProvider.quantize(direction: Vector3, reference: CFrame?): string
	if not reference then
		return "forward"
	end
	local forward = reference.LookVector
	local right = reference.RightVector
	local dotF = direction:Dot(forward)
	local dotR = direction:Dot(right)
	if math.abs(dotF) >= math.abs(dotR) then
		return dotF >= 0 and "forward" or "back"
	end
	return dotR >= 0 and "right" or "left"
end

return MovementDirectionProvider
