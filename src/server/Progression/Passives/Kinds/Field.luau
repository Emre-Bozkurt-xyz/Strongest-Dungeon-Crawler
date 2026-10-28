--!strict
-- kind = "field": a matching hit leaves a patch of ground that keeps working for a while.
--   { kind = "field", damageShare = 0.25, radius = 6, duration = 2, element = "Magic",
--     when = { delivery = { "area" } } }   -- deals 25% of the hit's damage per second within it
--   { kind = "field", status = "Chill", radius = 6, duration = 3 }   -- applies Chill within it
-- `damageShare` grows. One field per moment per effect, however many targets the hit reached. A
-- field's own damage is delivered as "field", so it never sets off area passives and chains.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local MasteryTracks = require(ReplicatedStorage.Shared.progression.MasteryTracks)

local Server = ServerScriptService.Server
local CombatService = require(Server.Services.CombatService)
local HitboxService = require(Server.SkillsFramework.HitboxService)
local Registrar = require(Server.Services.Registrar)
local Filters = require(script.Parent.Parent.Filters)
local KindTypes = require(script.Parent.Parent.KindTypes)
local KindUtil = require(script.Parent.Parent.KindUtil)
local StatusParams = require(script.Parent.Parent.StatusParams)

local TICK = 0.5
local ONCE_PER = 0.5
-- Damage with no element of its own (Magic) still reads as arcane.
local NEUTRAL_COLOR = Color3.fromRGB(140, 160, 255)

local ready = KindUtil.cooldown()

local function colorFor(effect: any): Color3
	local element = effect.element or (if effect.status == "Chill" then "Frost" else nil)
	local track = if element then MasteryTracks.forDamageType(element) else nil
	return if track and track.color then track.color else NEUTRAL_COLOR
end

-- The ground under `position`, ignoring the body that was hit.
local function groundBelow(position: Vector3, ignore: Instance?): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = if ignore then { ignore } else {}
	local result = workspace:Raycast(position, Vector3.new(0, -30, 0), params)
	return if result then result.Position else position
end

-- The visible patch: a thin disc on the ground under the hit, fading out as the field ends.
local function drawField(ground: Vector3, radius: number, duration: number, color: Color3)
	local disc = Instance.new("Part")
	disc.Name = "PassiveField"
	disc.Shape = Enum.PartType.Cylinder
	disc.Size = Vector3.new(0.2, radius * 2, radius * 2)
	disc.CFrame = CFrame.new(ground + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90))
	disc.Anchored = true
	disc.CanCollide = false
	disc.CanQuery = false
	disc.CanTouch = false
	disc.Material = Enum.Material.Neon
	disc.Color = color
	disc.Transparency = 0.7
	disc.Parent = workspace
	TweenService:Create(disc, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Transparency = 1,
	}):Play()
	Debris:AddItem(disc, duration + 0.1)
end

local function hitTotal(byType: { [string]: number }?): number
	local total = 0
	for _, amount in pairs(byType or {}) do
		total += amount
	end
	return total
end

local function runField(facts: Filters.HitFacts, active: KindTypes.Active, position: Vector3, struck: Instance?)
	local effect = active.effect
	local radius = effect.radius or 6
	local duration = effect.duration or 2
	local perTick = hitTotal(facts.byType) * (effect.damageShare or 0) * active.scale * TICK
	drawField(groundBelow(position, struck), radius, duration, colorFor(effect))
	task.spawn(function()
		local elapsed = 0
		while elapsed < duration do
			task.wait(TICK)
			elapsed += TICK
			local found = HitboxService.newQuery(CFrame.new(position))
				:casterEntityId(facts.sourceId)
				:factionRelation("enemy")
				:playersOnly(false)
				:sphere(radius)
				:collect({ collectIds = true })
			for _, id in ipairs(found.ids or {}) do
				local packets: { any } = {}
				if perTick > 0 then
					table.insert(packets, { type = "damage", damageType = effect.element or "Physical", amount = perTick })
				end
				if type(effect.status) == "string" then
					table.insert(packets, {
						type = "effect",
						effectId = effect.status,
						params = StatusParams.prepare(facts.sourceId, effect.status, nil),
					})
				end
				CombatService.applyAttack(id, {
					packets = packets,
					sourceId = facts.sourceId,
					metadata = { skillId = "Passive", delivery = "field", isCrit = false },
				}, facts.sourceId)
			end
		end
	end)
end

local Field: KindTypes.Kind = {
	kind = "field",
	afterHit = function(facts, actives)
		for _, active in ipairs(actives) do
			if
				Filters.matchesHit(active.effect.when, facts, nil)
				and ready(active.sourceId .. "|" .. facts.sourceId, ONCE_PER)
			then
				local model = Registrar.getEntityById(facts.targetId)
				local root = model and model:FindFirstChild("HumanoidRootPart") :: BasePart?
				if root then
					runField(facts, active, root.Position, model)
				end
			end
		end
	end,
}

return Field
