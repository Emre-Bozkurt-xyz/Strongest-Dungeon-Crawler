--!strict
-- Where the vitals readout sits on screen, as a binding updated every frame.
--
-- Following the character is done in screen space, not with a world-space surface: the readout
-- keeps one size at any zoom, never turns with the camera, and draws over effects and enemies. It
-- only borrows the character's projected position, so the readout reads as projected for the player
-- without the costs of being in the world.
--
-- Bound to render after the camera, so the projection uses this frame's camera and does not trail a
-- frame behind it. The result is still eased toward its target, which turns a dash or a knockback into
-- the readout catching up rather than jumping.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local React = require(ReplicatedStorage.Packages.React)
local DevTuningService = require(script.Parent.Parent.Parent.Parent.dev.DevTuningService)

-- Roughly head height above the root, for judging how far the camera is from the character.
local HEAD_HEIGHT = 1.5

local function readConfig(): any
	return DevTuningService.get("VitalsHud")
end

-- The centre the readout wants beside the character, or nil when there is no character to stand
-- beside: none spawned, the camera inside it, or the point behind the camera.
local function besideCharacter(camera: Camera, config: any, size: Vector2): Vector2?
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return nil
	end

	local follow = config.character
	local head = root.Position + Vector3.new(0, HEAD_HEIGHT, 0)
	if (camera.CFrame.Position - head).Magnitude < follow.minCameraDistance then
		return nil
	end

	-- Flattened so looking up or down does not push the readout above or below the character.
	local right = camera.CFrame.RightVector
	local flat = Vector3.new(right.X, 0, right.Z)
	if flat.Magnitude < 1e-3 then
		return nil
	end

	local world = root.Position + flat.Unit * (follow.side * follow.out) + Vector3.new(0, follow.up, 0)
	local point = camera:WorldToViewportPoint(world)
	if point.Z <= 0 then
		return nil
	end
	-- The projected point is the readout's inner edge, so it extends away from the character.
	return Vector2.new(point.X + follow.side * size.X / 2, point.Y)
end

local function pinned(viewport: Vector2, config: any, size: Vector2): Vector2
	return Vector2.new(viewport.X / 2, viewport.Y - config.pinned.bottom - size.Y / 2)
end

local function clampToViewport(centre: Vector2, viewport: Vector2, size: Vector2, margin: number): Vector2
	local halfW, halfH = size.X / 2, size.Y / 2
	return Vector2.new(
		math.clamp(centre.X, margin + halfW, math.max(margin + halfW, viewport.X - margin - halfW)),
		math.clamp(centre.Y, margin + halfH, math.max(margin + halfH, viewport.Y - margin - halfH))
	)
end

local function useVitalsAnchor(size: Vector2): React.Binding<UDim2>
	local position, setPosition = React.useBinding(UDim2.fromScale(0.5, 0.85))

	React.useEffect(function()
		local config = readConfig()
		local unsubscribe = DevTuningService.subscribe("VitalsHud", function()
			config = readConfig()
		end)

		local current: Vector2? = nil
		local name = `VitalsHudAnchor_{HttpService:GenerateGUID(false)}`
		RunService:BindToRenderStep(name, Enum.RenderPriority.Camera.Value + 1, function(dt: number)
			local camera = workspace.CurrentCamera
			if not camera then
				return
			end
			local viewport = camera.ViewportSize
			local target = (if config.anchor == "character" then besideCharacter(camera, config, size) else nil)
				or pinned(viewport, config, size)
			target = clampToViewport(target, viewport, size, config.character.margin)

			local smoothed = if current
				then current:Lerp(target, 1 - math.exp(-config.character.followRate * dt))
				else target
			current = smoothed
			-- Whole pixels: the readout is a CanvasGroup, which blurs at fractional offsets.
			setPosition(UDim2.fromOffset(math.round(smoothed.X), math.round(smoothed.Y)))
		end)

		return function()
			RunService:UnbindFromRenderStep(name)
			unsubscribe()
		end
	end, { size.X, size.Y })

	return position
end

return useVitalsAnchor
