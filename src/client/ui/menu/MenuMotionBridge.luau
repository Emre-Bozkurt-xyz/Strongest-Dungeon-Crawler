--!strict
-- The menu camera: pushed when the menu opens, popped when it closes.
--
-- The camera is not panel-owned: it keys off `modal.open` and applies to every menu view. React must
-- not reach above the SurfaceGui (R3), and a panel component is the wrong owner for a camera anyway.
-- Where the camera stands is MenuRigRuntime's to solve; this only hands that pose to the camera.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SharedConfig = require(ReplicatedStorage.Shared.Config)
local DevTuningService = require(script.Parent.Parent.Parent.dev.DevTuningService)
local MenuRigRuntime = require(script.Parent.MenuRigRuntime)

local CameraConfig = SharedConfig.Camera

local MenuMotionBridge = {}

local cameraModId: any = nil

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

	local tuned = DevTuningService.get("Camera.modifiers.systemMenuFocus")
	local modifier = table.clone(if type(tuned) == "table" then tuned else CameraConfig.modifiers.systemMenuFocus)
	modifier.poseProvider = function()
		return MenuRigRuntime.get():getCameraPose()
	end
	cameraModId = cam:pushModifier(modifier)
end

function MenuMotionBridge.popMenuCamera()
	getCamera():clearFocus()
	popCameraModifier()
end

function MenuMotionBridge.onModalStateChanged(prevOpen: boolean, nextOpen: boolean)
	if nextOpen and not prevOpen then
		MenuMotionBridge.pushMenuCamera()
	elseif prevOpen and not nextOpen then
		MenuMotionBridge.popMenuCamera()
	end
end

return MenuMotionBridge
