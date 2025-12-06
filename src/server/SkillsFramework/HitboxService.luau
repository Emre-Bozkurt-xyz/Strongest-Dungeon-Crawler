--!strict
-- HitboxService: primitive queries for skills and projectiles
--
-- Entity-based hitbox queries (sphere/box/cone/ray) with fluent builder API.
-- Works with registered entities (via Registrar) and supports faction-based filtering.
--
-- Example (builder):
-- local targetIds = HitboxService
--     .newQuery(originCFrame)
--     :casterEntityId(myEntityId)
--     :factionRelation("enemy")
--     :playersOnly(false)
--     :cone(60, 10)
--     :collect({ collectIds = true })

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local EntityUtils = require(ReplicatedStorage.Shared.EntityUtils)
local Registrar = require(game:GetService("ServerScriptService").Server.Services.Registrar)

local HitboxService = {}

-- Type definition for hitbox query options (shared by all queries)
export type QueryOptions = {
	casterEntityId: string?,
	playersOnly: boolean?,
	excludeModels: { Model }?,
	excludeEntityIds: { string }?,
	maxTargets: number?,
	includeCaster: boolean?,
	factionRelation: ("ally" | "enemy" | "neutral")?,
	filterInstances: { Instance }?,
	filterType: ("Include" | "Exclude")?,
	collisionGroup: string?,
}

-- Options controlling hitbox queries are defined in the export type QueryOptions below.

-- Fluent builder types
export type FactionRelation = "ally" | "enemy" | "neutral"
export type FilterType = "Include" | "Exclude"

-- Shape selected on the builder; only one applies at a time.
export type QueryShape =
	{ kind: "sphere", radius: number }
	| { kind: "cone", angleDeg: number, range: number }
	| { kind: "box", size: Vector3 }
	| { kind: "ray", length: number }

-- Chainable builder returned by `HitboxService.newQuery`.
export type HitboxQueryBuilder = {
	-- config
	--- Set absolute origin CFrame (overrides caster-derived origin if provided).
	origin: (self: HitboxQueryBuilder, cf: CFrame) -> HitboxQueryBuilder,
	--- Apply a relative transform (local-space) to the origin (offset/rotation).
	transform: (self: HitboxQueryBuilder, cf: CFrame) -> HitboxQueryBuilder,
	--- Translate the origin by local-space offset (studs). Z<0 moves forward.
	offset: (self: HitboxQueryBuilder, dx: number, dy: number, dz: number) -> HitboxQueryBuilder,
	--- Yaw rotate the origin by degrees around Y (local-space).
	yaw: (self: HitboxQueryBuilder, deg: number) -> HitboxQueryBuilder,
	--- Set the caster entity ID for this query (affects faction filtering and caster exclusion).
	casterEntityId: (self: HitboxQueryBuilder, entityId: string?) -> HitboxQueryBuilder,
	--- Limit results to player characters only (true) or include NPCs/other (false).
	playersOnly: (self: HitboxQueryBuilder, v: boolean) -> HitboxQueryBuilder,
	--- Allow the caster character to be included in results.
	includeCaster: (self: HitboxQueryBuilder, v: boolean) -> HitboxQueryBuilder,
	--- Faction relation filter: "ally", "enemy", or "neutral".
	factionRelation: (self: HitboxQueryBuilder, v: FactionRelation) -> HitboxQueryBuilder,
	--- Limit the number of models returned.
	maxTargets: (self: HitboxQueryBuilder, n: number) -> HitboxQueryBuilder,
	--- Exclude specific models from results.
	excludeModels: (self: HitboxQueryBuilder, list: { Model }) -> HitboxQueryBuilder,
	--- Exclude specific entity IDs from results.
	excludeEntityIds: (self: HitboxQueryBuilder, list: { string }) -> HitboxQueryBuilder,
	--- Provide overlap filter instances (descendant based).
	filterInstances: (self: HitboxQueryBuilder, list: { Instance }) -> HitboxQueryBuilder,
	--- Set filter behavior for filterInstances: "Include" or "Exclude".
	filterType: (self: HitboxQueryBuilder, v: FilterType) -> HitboxQueryBuilder,
	--- Set a collision group to respect during queries.
	collisionGroup: (self: HitboxQueryBuilder, name: string) -> HitboxQueryBuilder,

	-- shape selection
	--- Select a sphere query with the given radius.
	sphere: (self: HitboxQueryBuilder, radius: number) -> HitboxQueryBuilder,
	--- Select a cone query with angle (deg) and range (studs).
	cone: (self: HitboxQueryBuilder, angleDeg: number, range: number) -> HitboxQueryBuilder,
	--- Select a box query with size.
	box: (self: HitboxQueryBuilder, size: Vector3) -> HitboxQueryBuilder,
	--- Select a ray query with length (studs). Use :cast() to get RaycastResult.
	ray: (self: HitboxQueryBuilder, length: number) -> HitboxQueryBuilder,

	-- execution
	--- Execute the configured query and collect models. For rays, returns at most one model.
	--- If debug is true, attempts to draw the hitbox shape briefly.
	collect: (self: HitboxQueryBuilder, debug: boolean?) -> { Model },
	--- Cast the configured ray and return (top-level Model?, RaycastResult?). Only valid for ray shape.
	cast: (self: HitboxQueryBuilder) -> (Model?, RaycastResult?),
}

-- Returns HumanoidRootPart from a character model if present.
local function getHRP(character: Model): BasePart?
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- Returns the top-level model for any descendant instance.
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

-- Adds a model to an array if not already present.
local function addUnique(t: { Model }, m: Model)
	for _, v in ipairs(t) do
		if v == m then
			return
		end
	end
	t[#t + 1] = m
end

-- Core model-level exclusion logic using entity IDs and faction filtering.
local function shouldExclude(model: Model, opts: QueryOptions?): boolean
	if not opts then
		return false
	end
	
	local targetEntityId = Registrar.getEntityId(model)
	if not targetEntityId then
		return true -- Exclude non-registered entities
	end
	
	-- Exclude caster if requested
	if opts.casterEntityId and targetEntityId == opts.casterEntityId then
		if not opts.includeCaster then
			return true
		end
	end
	
	-- Explicit model exclusion
	local excl = opts.excludeModels
	if excl then
		for _, em in ipairs(excl) do
			if em == model then
				return true
			end
		end
	end
	
	-- Explicit entity ID exclusion
	local exclIds = opts.excludeEntityIds
	if exclIds then
		for _, eid in ipairs(exclIds) do
			if eid == targetEntityId then
				return true
			end
		end
	end
	
	-- Faction-based filtering
	if opts.factionRelation and opts.casterEntityId then
		local casterModel = Registrar.getEntityById(opts.casterEntityId)
		if casterModel then
			local casterFaction = EntityUtils.getFaction(casterModel)
			local targetFaction = EntityUtils.getFaction(model)
			
			if opts.factionRelation == "ally" then
				-- Only include allies (same faction)
				if casterFaction ~= targetFaction then
					return true
				end
			elseif opts.factionRelation == "enemy" then
				-- Only include enemies (different faction)
				if casterFaction == targetFaction then
					return true
				end
			elseif opts.factionRelation == "neutral" then
				-- Only include neutral (no faction relation check)
				-- This mode doesn't filter by faction
			end
		end
	end
	
	return false
end

-- Builds OverlapParams from filter options, or nil if no filters specified.
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

-- Query for models within a sphere.
-- @param origin CFrame Center of the sphere
-- @param radius number Radius in studs
-- @param opts QueryOptions|nil Optional filters and rules
-- @return {Model} Distinct models found (respecting opts)
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
				local targetEntityId = Registrar.getEntityId(m)
				if targetEntityId and Registrar.isPlayerEntity(targetEntityId) then
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

-- Query for models within a cone.
-- @param origin CFrame Cone origin and facing (LookVector)
-- @param angleDeg number Full cone angle in degrees
-- @param range number Cone range in studs
-- @param opts QueryOptions|nil Optional filters and rules
-- @return {Model} Distinct models found (respecting opts)
function HitboxService.queryCone(origin: CFrame, angleDeg: number, range: number, opts: QueryOptions?): { Model }
	local results: { Model } = {}
	local forward = origin.LookVector
	local halfAngle = math.rad(angleDeg * 0.5)
	local overlap = buildOverlapParams(opts)
	local parts = Workspace:GetPartBoundsInRadius(origin.Position, range, overlap)
	for _, part in ipairs(parts) do
		local m = modelOf(part)
		if m and not shouldExclude(m, opts) then
			local hrp = getHRP(m)
			if hrp then
				local toTarget = (hrp.Position - origin.Position)
				local dist = toTarget.Magnitude
				if dist > 0 then
					local dir = toTarget.Unit
					local dot = math.clamp(forward:Dot(dir), -1, 1)
					local angle = math.acos(dot)
					if angle <= halfAngle then
						if not opts or not opts.playersOnly then
							addUnique(results, m)
						else
							local targetEntityId = Registrar.getEntityId(m)
							if targetEntityId and Registrar.isPlayerEntity(targetEntityId) then
								addUnique(results, m)
							end
						end
						if opts and opts.maxTargets and #results >= opts.maxTargets then
							break
						end
					end
				end
			end
		end
	end
	return results
end

-- Query for models intersecting an oriented box.
-- @param cframe CFrame Box center/orientation
-- @param size Vector3 Box size (X,Y,Z)
-- @param opts QueryOptions|nil Optional filters and rules
-- @return {Model} Distinct models found (respecting opts)
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
				local targetEntityId = Registrar.getEntityId(m)
				if targetEntityId and Registrar.isPlayerEntity(targetEntityId) then
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

-- Raycast forward from origin by length.
-- Always excludes the caster's character from the ray.
-- @param origin CFrame Ray origin and direction (LookVector)
-- @param length number Distance in studs
-- @param opts QueryOptions|nil Optional filters and rules
-- @return Model? The hit model (top-level), if any
-- @return RaycastResult? The raw raycast result, if any
function HitboxService.queryRay(origin: CFrame, length: number, opts: QueryOptions?): (Model?, RaycastResult?)
	local params = RaycastParams.new()
	if opts and opts.filterInstances and #opts.filterInstances > 0 then
		params.FilterDescendantsInstances = opts.filterInstances
		params.FilterType = (opts.filterType == "Exclude") and Enum.RaycastFilterType.Exclude
			or Enum.RaycastFilterType.Include
	end
	if opts and opts.collisionGroup then
		params.CollisionGroup = opts.collisionGroup
	end
	-- Always exclude caster model to avoid self-hits
	if opts and opts.casterEntityId then
		local casterModel = Registrar.getEntityById(opts.casterEntityId)
		if casterModel then
			local list: { Instance } = {}
			if params.FilterDescendantsInstances then
				for _, inst in ipairs(params.FilterDescendantsInstances) do
					list[#list + 1] = inst
				end
			end
			list[#list + 1] = casterModel :: Instance
			params.FilterDescendantsInstances = list
			params.FilterType = Enum.RaycastFilterType.Exclude
		end
	end
	local dir = origin.LookVector * length
	local res = Workspace:Raycast(origin.Position, dir, params)
	if res and res.Instance then
		return modelOf(res.Instance), res
	end
	return nil, nil
end

function HitboxService.getEntityIds(targets: { Model } | Model): { string }
	local result = {}
	if typeof(targets) == "table" then
		for _, model in ipairs(targets) do
			local entityId = Registrar.getEntityId(model)
			if entityId then
				table.insert(result, entityId)
			end
		end
	else
		local entityId = Registrar.getEntityId(targets)
		if entityId then
			table.insert(result, entityId)
		end
	end
	return result
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

-- Debug-only: draw a translucent sphere at origin for duration seconds.
function HitboxService.debugDrawSphere(origin: CFrame, radius: number, duration: number?)
	makePart(
		origin,
		Vector3.new(radius * 2, radius * 2, radius * 2),
		Color3.fromRGB(0, 170, 255),
		Enum.PartType.Ball,
		duration or 0.5
	)
end

-- Debug-only: draw a translucent box for duration seconds.
function HitboxService.debugDrawBox(cf: CFrame, size: Vector3, duration: number?)
	makePart(cf, size, Color3.fromRGB(255, 170, 0), nil, duration or 0.5)
end

-- Debug-only: draw a thin box representing a ray forward for duration seconds.
function HitboxService.debugDrawRay(origin: CFrame, length: number, duration: number?, color: Color3?, width: number?)
	local size = Vector3.new(width or 0.2, width or 0.2, length)
	local cf = origin * CFrame.new(0, 0, -length * 0.5)
	makePart(cf, size, color or Color3.fromRGB(170, 255, 0), nil, duration or 0.5)
end

--
-- Fluent query builder
-- Construct with `HitboxService.newQuery(origin?: CFrame)` and chain setters.
-- If origin is omitted, the builder will attempt to derive it from `caster.HumanoidRootPart`.
--
-- Example:
-- local qb = HitboxService.newQuery()
--     :caster(player)
--     :playersOnly(false)
--     :teamRelation("enemy")
--     :respectPvP(true)
--     :cone(40, 8)
-- local models = qb:collect()

-- Internal builder object factory
local function makeBuilder(originCf: CFrame?): HitboxQueryBuilder
	local opts: QueryOptions = {
		playersOnly = false,
		includeCaster = false,
		factionRelation = "enemy",
	}
	local shape: QueryShape? = nil
	local origin: CFrame? = originCf
	local localXform: CFrame = CFrame.new()

	local b = {} :: any

	-- placement/origin helpers
	-- allow overriding absolute origin
	function b:origin(cf: CFrame): HitboxQueryBuilder
		origin = cf
		return (b :: any) :: HitboxQueryBuilder
	end
	-- apply a local-space transform relative to origin/caster HRP
	function b:transform(cf: CFrame): HitboxQueryBuilder
		localXform = localXform * cf
		return (b :: any) :: HitboxQueryBuilder
	end
	-- translate in local space; Z<0 forward
	function b:offset(dx: number, dy: number, dz: number): HitboxQueryBuilder
		localXform = localXform * CFrame.new(dx, dy, dz)
		return (b :: any) :: HitboxQueryBuilder
	end
	-- yaw rotate around Y in local space (degrees)
	function b:yaw(deg: number): HitboxQueryBuilder
		local rad = math.rad(deg)
		localXform = localXform * CFrame.Angles(0, rad, 0)
		return (b :: any) :: HitboxQueryBuilder
	end

	-- config setters
	-- Set the caster entity ID for this query (affects faction filtering and caster exclusion).
	function b:casterEntityId(entityId: string?): HitboxQueryBuilder
		opts.casterEntityId = entityId
		return (b :: any) :: HitboxQueryBuilder
	end
	-- Limit results to player characters only (true) or include NPCs/other (false).
	function b:playersOnly(v: boolean): HitboxQueryBuilder
		opts.playersOnly = v
		return (b :: any) :: HitboxQueryBuilder
	end
	-- Allow the caster character to be included in results.
	function b:includeCaster(v: boolean): HitboxQueryBuilder
		opts.includeCaster = v
		return (b :: any) :: HitboxQueryBuilder
	end
	-- Faction relation filter: "ally", "enemy", or "neutral".
	function b:factionRelation(v: FactionRelation): HitboxQueryBuilder
		opts.factionRelation = v
		return (b :: any) :: HitboxQueryBuilder
	end
	-- Limit the number of models returned.
	function b:maxTargets(n: number): HitboxQueryBuilder
		opts.maxTargets = n
		return (b :: any) :: HitboxQueryBuilder
	end
	-- Exclude specific models from results.
	function b:excludeModels(list: { Model }): HitboxQueryBuilder
		opts.excludeModels = list
		return (b :: any) :: HitboxQueryBuilder
	end
	-- Exclude specific entity IDs from results.
	function b:excludeEntityIds(list: { string }): HitboxQueryBuilder
		opts.excludeEntityIds = list
		return (b :: any) :: HitboxQueryBuilder
	end
	-- Provide overlap filter instances (descendant based).
	function b:filterInstances(list: { Instance }): HitboxQueryBuilder
		opts.filterInstances = list
		return (b :: any) :: HitboxQueryBuilder
	end
	-- Set filter behavior for filterInstances: "Include" or "Exclude".
	function b:filterType(v: FilterType): HitboxQueryBuilder
		opts.filterType = v
		return (b :: any) :: HitboxQueryBuilder
	end
	-- Set a collision group to respect during queries.
	function b:collisionGroup(name: string): HitboxQueryBuilder
		opts.collisionGroup = name
		return (b :: any) :: HitboxQueryBuilder
	end

	-- shape selection
	-- Select a sphere query with the given radius.
	function b:sphere(radius: number): HitboxQueryBuilder
		shape = { kind = "sphere", radius = radius }
		return (b :: any) :: HitboxQueryBuilder
	end
	-- Select a cone query with angle (deg) and range (studs).
	function b:cone(angleDeg: number, range: number): HitboxQueryBuilder
		shape = { kind = "cone", angleDeg = angleDeg, range = range }
		return (b :: any) :: HitboxQueryBuilder
	end
	-- Select a box query with size.
	function b:box(size: Vector3): HitboxQueryBuilder
		shape = { kind = "box", size = size }
		return (b :: any) :: HitboxQueryBuilder
	end
	-- Select a ray query with length (studs). Use :cast() to get RaycastResult.
	function b:ray(length: number): HitboxQueryBuilder
		shape = { kind = "ray", length = length }
		return (b :: any) :: HitboxQueryBuilder
	end

	-- execution helpers
	local function ensureOrigin(): CFrame
		if origin then
			return origin * localXform
		end
		-- derive from caster entity if possible
		if opts.casterEntityId then
			local entity = Registrar.getEntityById(opts.casterEntityId)
			if entity then
				local hrp: BasePart? = entity:FindFirstChild("HumanoidRootPart") :: BasePart?
				if hrp then
					return hrp.CFrame * localXform
				end
			end
		end
		-- fallback to identity
		return CFrame.new() * localXform
	end

	-- Execute the configured query and collect models.
	-- For ray queries, returns a list with at most one model.
	function b:collect(params: any?): { Model | string }
		local debug = params and params.debug or false
		local collectIds = params and params.collectIds or true
		local cf = ensureOrigin()
		if not shape then
			return {}
		end
		local result = {}
		if shape.kind == "sphere" then
			if debug then
				HitboxService.debugDrawSphere(cf, shape.radius)
			end
			result = HitboxService.querySphere(cf, shape.radius, opts)
		elseif shape.kind == "cone" then
			if debug then
				-- Approximate cone by drawing forward and boundary rays
				local half = math.rad(shape.angleDeg * 0.5)
				HitboxService.debugDrawRay(cf, shape.range)
				HitboxService.debugDrawRay(
					cf * CFrame.Angles(0, half, 0),
					shape.range,
					nil,
					Color3.fromRGB(0, 13, 255),
					0.07
				)
				HitboxService.debugDrawRay(
					cf * CFrame.Angles(0, -half, 0),
					shape.range,
					nil,
					Color3.fromRGB(0, 13, 255),
					0.07
				)
			end
			result = HitboxService.queryCone(cf, shape.angleDeg, shape.range, opts)
		elseif shape.kind == "box" then
			if debug then
				HitboxService.debugDrawBox(cf, shape.size)
			end
			result = HitboxService.queryBox(cf, shape.size, opts)
		else -- ray
			local len = (shape :: any).length
			if debug then
				HitboxService.debugDrawRay(cf, len)
			end
			local model: Model?, _ = HitboxService.queryRay(cf, len, opts)
			local list: { Model } = {}
			if model then
				list[1] = model
			end
			result = list
		end

		if collectIds then
			return HitboxService.getEntityIds(result)
		end
		return result
	end

	-- Cast the configured ray and return (top-level Model?, RaycastResult?).
	-- Only valid for ray shape; otherwise returns (nil, nil).
	function b:cast(): (Model?, RaycastResult?)
		local cf = ensureOrigin()
		if not shape or shape.kind ~= "ray" then
			return nil, nil
		end
		return HitboxService.queryRay(cf, shape.length, opts)
	end

	return (b :: any) :: HitboxQueryBuilder
end

-- Create a new fluent query builder. If origin is omitted, one will be derived from caster HRP when executing.
function HitboxService.newQuery(origin: CFrame?): HitboxQueryBuilder
	return makeBuilder(origin)
end

return HitboxService
