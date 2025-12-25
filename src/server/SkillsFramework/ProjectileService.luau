--!strict
-- ProjectileService stub: spawns and owns projectile simulation.

local RunService = game:GetService("RunService")

local ProjectileService = {}

export type SpawnParams = {
	caster: Player,
	defId: string,
	fxKey: string?,
	origin: Vector3,
	dir: Vector3,
	speed: number,
	gravityY: number?,
	radius: number?,
	lifetime: number?,
	pierce: number?,
}

local nextId = 0
local active: { [number]: any } = {}

local function newId(): number
	nextId += 1
	return nextId
end

function ProjectileService.spawn(p: SpawnParams): number
	local id = newId()
	active[id] = {
		id = id,
		caster = p.caster,
		pos = p.origin,
		vel = p.dir * p.speed,
		gY = p.gravityY or 0,
		radius = p.radius or 1.5,
		life = p.lifetime or 1.5,
		pierce = p.pierce or 1,
		fxKey = p.fxKey,
	}
	return id
end

local accum = 0
RunService.Heartbeat:Connect(function(dt)
	accum += dt
	if accum > 1e6 then -- guard
		accum = 0
	end
	for id, pr in pairs(active) do
		pr.life -= dt
		if pr.life <= 0 then
			active[id] = nil
			continue
		end
		-- simple kinematics; no collision yet
		pr.vel += Vector3.new(0, pr.gY, 0) * dt
		pr.pos += pr.vel * dt
	end
end)

return ProjectileService
