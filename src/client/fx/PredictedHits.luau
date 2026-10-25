--!strict
-- PredictedHits: the local reaction to the caster's own melee hits, on the frame they land.
--
-- Each hit fires on the same schedule and against the same cone (MeleeHits) the server resolves, so
-- what flashes here is what the server is about to damage. Only reactions are predicted -- flash,
-- hit sound, hitstop, a jolt on the target's health bar. Damage numbers and health stay on the
-- server's confirmation: dodges, crits and mitigation are rolled there, and a predicted number that
-- turns into a miss reads worse than one that arrives a moment later.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MeleeHits = require(ReplicatedStorage.Shared.skills.MeleeHits)
local EntityUtils = require(ReplicatedStorage.Shared.EntityUtils)
local Registrar = require(script.Parent.Parent.Services.Registrar)
local EntityStore = require(script.Parent.Parent.Entities.EntityStore)
local ImmediateHitFeedback = require(script.Parent.ImmediateHitFeedback)
local Hitstop = require(script.Parent.Hitstop)

export type ScheduleOptions = {
	hits: { MeleeHits.Hit },
	-- Tempo scaling the server applies to the same hits.
	durationScale: number,
	-- False once the cast this schedule belongs to is cancelled or superseded.
	isCurrent: () -> boolean,
	-- The swing to freeze on contact, read when the hit lands.
	getTrack: () -> AnimationTrack?,
	hitSounds: { string }?,
}

local PredictedHits = {}

local function rootOf(model: Model): BasePart?
	local root = model:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function resolve(hit: MeleeHits.Hit, options: ScheduleOptions)
	local character = Players.LocalPlayer.Character
	local casterRoot = character and rootOf(character)
	if not character or not casterRoot then
		return
	end

	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = { character }

	local casterFaction = EntityUtils.getFaction(character)
	local origin = MeleeHits.originFor(casterRoot.CFrame, hit)
	local targets = MeleeHits.queryCone(origin, hit.angle, hit.range, overlap, function(model: Model): boolean
		local id = Registrar.getEntityId(model)
		return id ~= nil and EntityUtils.getFaction(model) ~= casterFaction and EntityStore.isAlive(id)
	end)
	if #targets == 0 then
		return
	end

	local nearest: Vector3? = nil
	local nearestDistance = math.huge
	for _, target in ipairs(targets) do
		ImmediateHitFeedback.flashTarget(target)
		local id = Registrar.getEntityId(target)
		if id then
			EntityStore.markStruck(id)
		end
		local root = rootOf(target)
		if root then
			local distance = (root.Position - origin.Position).Magnitude
			if distance < nearestDistance then
				nearest = root.Position
				nearestDistance = distance
			end
		end
	end
	if nearest then
		ImmediateHitFeedback.playHitSound(nearest, options.hitSounds)
	end
	if hit.hitstop then
		Hitstop.apply(options.getTrack())
	end
end

function PredictedHits.schedule(options: ScheduleOptions)
	for _, hit in ipairs(options.hits) do
		task.delay(hit.t * options.durationScale, function()
			if options.isCurrent() then
				resolve(hit, options)
			end
		end)
	end
end

return PredictedHits
