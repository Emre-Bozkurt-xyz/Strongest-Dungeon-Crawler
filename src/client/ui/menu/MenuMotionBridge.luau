--!strict

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldGUIManager = require(script.Parent.Parent.Parent.WorldGUIManager)
local SharedConfig = require(ReplicatedStorage.Shared.Config)
local DevTuningService = require(script.Parent.Parent.Parent.dev.DevTuningService)

local UIMenuConfig = SharedConfig.UIMenu

local MenuMotionBridge = {}

local function resolveGroupName(): string
	local tuned = DevTuningService.get("UIMenu.groupName")
	if type(tuned) == "string" and tuned ~= "" then
		return tuned
	end
	return UIMenuConfig.groupName
end

local function getYawFromCharacterOrCamera(): number?
	local player = Players.LocalPlayer
	local character = player and player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		local forward = hrp.CFrame.LookVector
		local flat = Vector3.new(forward.X, 0, forward.Z)
		if flat.Magnitude > 1e-4 then
			flat = flat.Unit
			return math.atan2(-flat.X, -flat.Z)
		end
	end

	local camera = Workspace.CurrentCamera
	if camera then
		local look = camera.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude > 1e-4 then
			flat = flat.Unit
			return math.atan2(-flat.X, -flat.Z)
		end
	end
	return nil
end

function MenuMotionBridge.captureEntryBasis()
	local wg = WorldGUIManager.peekInstance()
	if not wg then
		return
	end
	local yaw = getYawFromCharacterOrCamera()
	if type(yaw) == "number" then
		wg:setGroupBasisYaw(resolveGroupName(), yaw)
	end
end

function MenuMotionBridge.clearEntryBasis()
	local wg = WorldGUIManager.peekInstance()
	if not wg then
		return
	end
	wg:setGroupBasisYaw(resolveGroupName(), nil)
end

function MenuMotionBridge.onModalStateChanged(prevOpen: boolean, nextOpen: boolean)
	if nextOpen and not prevOpen then
		MenuMotionBridge.captureEntryBasis()
	elseif prevOpen and not nextOpen then
		MenuMotionBridge.clearEntryBasis()
	end
end

return MenuMotionBridge
