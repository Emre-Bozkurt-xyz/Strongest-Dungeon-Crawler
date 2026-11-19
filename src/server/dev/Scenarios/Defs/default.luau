--!strict
-- The baseplate sandbox every dev server starts in: a training dummy, a slime that comes back ten
-- seconds after it dies, and a placeholder attunement shrine. Each stands at a world marker of its
-- name when the baseplate has one (DummySpot, SlimeSpot, Shrine), else at its usual spot.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Attunement = require(ReplicatedStorage.Shared.progression.Attunement)
local Stages = require(script:FindFirstAncestor("dev").Stages)

local function spot(name: string, fallback: Vector3): CFrame
	return Stages.worldMarker(name) or CFrame.new(fallback)
end

-- A stand-in Attunement Shrine: a slab, a pillar and a floating crystal, tagged so
-- AttunementService gives it a prompt. Real shrines are placed in maps with the same tag.
local function buildShrine(at: Vector3, parent: Instance): Model
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { game:GetService("Players"):GetChildren() }
	local hit = workspace:Raycast(at + Vector3.new(0, 100, 0), Vector3.new(0, -400, 0), params)
	local ground = if hit then hit.Position.Y else at.Y

	local model = Instance.new("Model")
	model.Name = "AttunementShrine"
	local function part(name: string, size: Vector3, y: number, props: { [string]: any }): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Anchored = true
		p.CFrame = CFrame.new(at.X, ground + y, at.Z)
		for key, value in pairs(props) do
			(p :: any)[key] = value
		end
		p.Parent = model
		return p
	end
	local stone = Color3.fromRGB(70, 72, 82)
	local base = part("Base", Vector3.new(7, 0.8, 7), 0.4, { Material = Enum.Material.Slate, Color = stone })
	part("Pillar", Vector3.new(1.6, 3.4, 1.6), 0.8 + 1.7, { Material = Enum.Material.Slate, Color = stone })
	local crystal = part("Crystal", Vector3.new(1, 1.8, 1), 6, {
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(120, 200, 255),
		CanCollide = false,
		CastShadow = false,
	})
	crystal.CFrame *= CFrame.Angles(0, math.rad(45), math.rad(45))
	local light = Instance.new("PointLight")
	light.Color = crystal.Color
	light.Range = 12
	light.Brightness = 1.5
	light.Parent = crystal
	model.PrimaryPart = base
	model.Parent = parent
	CollectionService:AddTag(model, Attunement.SHRINE_TAG)
	return model
end

return {
	title = "Sandbox",
	description = "The baseplate world with a training dummy, a respawning slime and an attunement shrine.",
	setup = function(s)
		s.spawn("Dummy", spot("DummySpot", Vector3.new(90, 0, 0)))
		s.spawn("Slime", spot("SlimeSpot", Vector3.new(100, 0, 0)), { respawnDelay = 10 })
		s.track(buildShrine(spot("Shrine", Vector3.new(80, 0, -14)).Position, s.folder))
	end,
}
