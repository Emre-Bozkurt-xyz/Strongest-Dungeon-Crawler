--!strict
-- HitboxService: primitive queries for skills and projectiles

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local HitboxService = {}

export type QueryOptions = {
	caster: Player?,
	playersOnly: boolean?,
	excludeModels: { Model }?,
	maxTargets: number?,
	-- team filtering
	teamRelation: ("ally" | "enemy")?,
	-- overlap filters
	filterInstances: { Instance }?,
	filterType: ("Include" | "Exclude")?,
	collisionGroup: string?,
}

local function getHRP(character: Model): BasePart?
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function modelOf(inst: Instance): Model?
	local cur: Instance? = inst
	while cur do
		if cur:IsA("Model") then
			return cur
		end
		cur = cur.Parent
	end
	return nil
end

local function addUnique(t: { Model }, m: Model)
	for _, v in ipairs(t) do
		if v == m then
			return
		end
	end
	t[#t + 1] = m
end

local function isAlly(a: Player?, b: Player?): boolean
	if not a or not b then
		return false
	end
	local ta = a.Team
	local tb = b.Team
	if ta and tb then
		return ta == tb
	end
	return false
end

local function shouldExclude(model: Model, opts: QueryOptions?): boolean
	if not opts then
		return false
	end
	if opts.caster and opts.caster.Character == model then
		return true
	end
	local excl = opts.excludeModels
	if excl then
		for _, em in ipairs(excl) do
			if em == model then
				return true
			end
		end
	end
	-- team filtering (players only)
	if opts.teamRelation and opts.caster then
		local plr = Players:GetPlayerFromCharacter(model)
		if plr then
			local ally = isAlly(opts.caster, plr)
			if opts.teamRelation == "ally" and not ally then
				return true
			end
			if opts.teamRelation == "enemy" and ally then
				return true
			end
		end
	end
	return false
end

local function buildOverlapParams(opts: QueryOptions?): OverlapParams?
	if not opts then
		return nil
	end
	local hasFilters = (opts.filterInstances and #opts.filterInstances > 0) or opts.collisionGroup ~= nil
	if not hasFilters then
		return nil
	end
	local p = OverlapParams.new()
	if opts.filterInstances and #opts.filterInstances > 0 then
		p.FilterDescendantsInstances = opts.filterInstances
		local ft = opts.filterType == "Exclude" and Enum.RaycastFilterType.Exclude or Enum.RaycastFilterType.Include
		p.FilterType = ft
	end
	if opts.collisionGroup then
		p.CollisionGroup = opts.collisionGroup
	end
	return p
end

function HitboxService.querySphere(origin: CFrame, radius: number, opts: QueryOptions?): { Model }
	local results: { Model } = {}
	local overlap = buildOverlapParams(opts)
	local parts = Workspace:GetPartBoundsInRadius(origin.Position, radius, overlap)
	for _, part in ipairs(parts) do
		local m = modelOf(part)
		if m and not shouldExclude(m, opts) then
			if not opts or not opts.playersOnly then
				addUnique(results, m)
			else
				local plr = Players:GetPlayerFromCharacter(m)
				if plr then
					addUnique(results, m)
				end
			end
		end
		if opts and opts.maxTargets and #results >= opts.maxTargets then
			break
		end
	end
	return results
end

function HitboxService.queryCone(origin: CFrame, angleDeg: number, range: number, opts: QueryOptions?): { Model }
	local results: { Model } = {}
	local forward = origin.LookVector
	local halfAngle = math.rad(angleDeg * 0.5)
	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		if char then
			if opts and opts.caster and plr == opts.caster then
				-- skip caster
			else
				if not shouldExclude(char, opts) then
					local hrp = getHRP(char)
					if hrp then
						local toTarget = (hrp.Position - origin.Position)
						local dist = toTarget.Magnitude
						if dist <= range and dist > 0 then
							local dir = toTarget.Unit
							local dot = math.clamp(forward:Dot(dir), -1, 1)
							local angle = math.acos(dot)
							if angle <= halfAngle then
								addUnique(results, char)
								if opts and opts.maxTargets and #results >= opts.maxTargets then
									break
								end
							end
						end
					end
				end
			end
		end
	end
	return results
end

function HitboxService.queryBox(cframe: CFrame, size: Vector3, opts: QueryOptions?): { Model }
	local results: { Model } = {}
	local overlap = buildOverlapParams(opts)
	local parts = Workspace:GetPartBoundsInBox(cframe, size, overlap)
	for _, part in ipairs(parts) do
		local m = modelOf(part)
		if m and not shouldExclude(m, opts) then
			if not opts or not opts.playersOnly then
				addUnique(results, m)
			else
				local plr = Players:GetPlayerFromCharacter(m)
				if plr then
					addUnique(results, m)
				end
			end
		end
		if opts and opts.maxTargets and #results >= opts.maxTargets then
			break
		end
	end
	return results
end

function HitboxService.queryRay(origin: CFrame, length: number, opts: QueryOptions?)
	local params = RaycastParams.new()
	if opts and opts.filterInstances and #opts.filterInstances > 0 then
		params.FilterDescendantsInstances = opts.filterInstances
		params.FilterType = (opts.filterType == "Exclude") and Enum.RaycastFilterType.Exclude
			or Enum.RaycastFilterType.Include
	end
	if opts and opts.collisionGroup then
		params.CollisionGroup = opts.collisionGroup
	end
	local dir = origin.LookVector * length
	local res = Workspace:Raycast(origin.Position, dir, params)
	if res and res.Instance then
		return modelOf(res.Instance), res
	end
	return nil, nil
end

-- simple debug draw (server-side parts)
local function makePart(cf: CFrame, size: Vector3, color: Color3, shape: Enum.PartType?, duration: number)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Transparency = 0.5
	p.CFrame = cf
	p.Size = size
	if shape then
		p.Shape = shape
	end
	p.Name = "HB_Debug"
	p.Parent = Workspace
	task.delay(duration, function()
		if p then
			p:Destroy()
		end
	end)
end

function HitboxService.debugDrawSphere(origin: CFrame, radius: number, duration: number?)
	makePart(
		origin,
		Vector3.new(radius * 2, radius * 2, radius * 2),
		Color3.fromRGB(0, 170, 255),
		Enum.PartType.Ball,
		duration or 0.5
	)
end

function HitboxService.debugDrawBox(cf: CFrame, size: Vector3, duration: number?)
	makePart(cf, size, Color3.fromRGB(255, 170, 0), nil, duration or 0.5)
end

function HitboxService.debugDrawRay(origin: CFrame, length: number, duration: number?)
	local size = Vector3.new(0.2, 0.2, length)
	local cf = origin * CFrame.new(0, 0, -length * 0.5)
	makePart(cf, size, Color3.fromRGB(170, 255, 0), nil, duration or 0.5)
end

return HitboxService
