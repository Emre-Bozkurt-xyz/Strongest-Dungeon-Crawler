--!strict
-- Imperative motion that belongs to the menu as a whole rather than to any one panel: the world-GUI
-- group's entry yaw, and the camera pose the menu is viewed from.
--
-- The camera half used to live in SystemPanelRuntime, which made it look panel-owned. It never was:
-- it keys off `modal.open` and looks at MenuRigRuntime's focus point, so it applies to every menu
-- view. It moved here when SystemPanel became a React panel, because React must not reach above the
-- SurfaceGui (R3) and a panel component is the wrong owner for a camera.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldGUIManager = require(script.Parent.Parent.Parent.WorldGUIManager)
local SharedConfig = require(ReplicatedStorage.Shared.Config)
local DevTuningService = require(script.Parent.Parent.Parent.dev.DevTuningService)
local MenuRigRuntime = require(script.Parent.MenuRigRuntime)

local UIMenuConfig = SharedConfig.UIMenu
local CameraConfig = SharedConfig.Camera

local MenuMotionBridge = {}

-- SystemPanelRuntime used to push this itself; it no longer runs, so this bridge owns it.
local OWNS_MENU_CAMERA = true

local cameraModId: any = nil

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

local function cloneMenuCameraModifier()
	local tuned = DevTuningService.get("Camera.modifiers.systemMenuFocus")
	local source = if type(tuned) == "table" then tuned else CameraConfig.modifiers.systemMenuFocus
	local modifier = table.clone(source)
	-- The nested tables are cloned too: the modifier is mutated below, and sharing them would edit
	-- the config for every later push.
	if modifier.yawAssist then
		modifier.yawAssist = table.clone(modifier.yawAssist)
	end
	if modifier.lookTarget then
		modifier.lookTarget = table.clone(modifier.lookTarget)
	end
	return modifier
end

local function applyMenuCameraPose(cam: any, modifier: any)
	local basisYaw = MenuRigRuntime.get():getBasisYaw()
	if type(basisYaw) ~= "number" then
		return
	end

	local entryPose = modifier.entryPose
	local yawOffset = 0
	local pitch = nil
	if type(entryPose) == "table" then
		if type(entryPose.yawOffset) == "number" then
			yawOffset = entryPose.yawOffset
		end
		if type(entryPose.pitch) == "number" then
			pitch = entryPose.pitch
		end
	end

	cam:setAngles(basisYaw + yawOffset, pitch)
end

local function getCamera(): any
	local CameraController = require(script.Parent.Parent.Parent.CameraController)
	return CameraController.getInstance()
end

local function popCameraModifier()
	if not cameraModId then
		return
	end
	getCamera():popModifier(cameraModId)
	cameraModId = nil
end

function MenuMotionBridge.pushMenuCamera()
	local cam = getCamera()
	cam:clearFocus()
	popCameraModifier()

	local modifier = cloneMenuCameraModifier()
	applyMenuCameraPose(cam, modifier)
	-- Resolved per frame rather than captured: the rig's focus point moves as panels open and close.
	modifier.lookAtProvider = function()
		return MenuRigRuntime.get():getFocusPoint()
	end
	cameraModId = cam:pushModifier(modifier)
end

function MenuMotionBridge.popMenuCamera()
	getCamera():clearFocus()
	popCameraModifier()
end

function MenuMotionBridge.onModalStateChanged(prevOpen: boolean, nextOpen: boolean)
	if nextOpen and not prevOpen then
		MenuMotionBridge.captureEntryBasis()
		if OWNS_MENU_CAMERA then
			MenuMotionBridge.pushMenuCamera()
		end
	elseif prevOpen and not nextOpen then
		MenuMotionBridge.clearEntryBasis()
		if OWNS_MENU_CAMERA then
			MenuMotionBridge.popMenuCamera()
		end
	end
end

return MenuMotionBridge
