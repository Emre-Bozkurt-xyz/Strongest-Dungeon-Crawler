--!strict
-- Resolves the world point the player is currently aiming at, for skills that need a direction the
-- caster's facing cannot supply (projectile basic attacks).
--
-- Resolves a POINT, not a direction. The muzzle a projectile leaves from is offset from the camera
-- by most of a character's width, so firing parallel to the camera ray misses everything the cursor
-- is over, worsening with distance. Aiming the muzzle *at* the resolved point converges at every
-- range.
--
-- Cursor handling covers both camera states without branching: under MouseBehavior.LockCenter
-- GetMouseLocation returns screen centre, and when the cursor is unlocked for UI it returns the real
-- pointer.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local AimResolver = {}

-- Where to place the aim point when the cursor is over open sky.
local MAX_AIM_DISTANCE = 500

local function getIgnoreList(): { Instance }
	local ignore: { Instance } = {}

	local character = Players.LocalPlayer and Players.LocalPlayer.Character
	if character then
		table.insert(ignore, character)
	end

	-- Projectile visuals are non-colliding but still raycast-visible; without this, aiming at your
	-- own last bolt drags every subsequent shot toward it.
	local projectiles = Workspace:FindFirstChild("Projectiles")
	if projectiles then
		table.insert(ignore, projectiles)
	end
	local projectileDebug = Workspace:FindFirstChild("_ProjectileDebug")
	if projectileDebug then
		table.insert(ignore, projectileDebug)
	end

	return ignore
end

-- The world point under the cursor, or a far point along the cursor ray when it hits nothing.
-- Returns nil only when there is no camera to raycast from, in which case callers should omit aim
-- entirely and let the server fall back to the caster's facing.
function AimResolver.getAimPoint(): Vector3?
	local camera = Workspace.CurrentCamera
	if not camera then
		return nil
	end

	local mouseLocation = UserInputService:GetMouseLocation()
	local ray = camera:ScreenPointToRay(mouseLocation.X, mouseLocation.Y)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = getIgnoreList()
	params.IgnoreWater = true

	local result = Workspace:Raycast(ray.Origin, ray.Direction * MAX_AIM_DISTANCE, params)
	if result then
		return result.Position
	end

	return ray.Origin + ray.Direction * MAX_AIM_DISTANCE
end

return AimResolver
