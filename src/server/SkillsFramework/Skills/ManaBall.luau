-- ManaBall: Fires a single magic projectile, scales on magic, uses mana
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Server = ServerScriptService.Server

local BaseSkill = require(script.Parent.BaseSkill)
local ProjectileService = require(Server.Services.ProjectileService)
local CombatService = require(Server.Services.CombatService)
local Registrar = require(Server.Services.Registrar)
local EntityUtils = require(ReplicatedStorage.Shared.EntityUtils)
local StatTypes = require(ReplicatedStorage.Shared.StatTypes)

local ManaBall = {}
ManaBall.__index = ManaBall
setmetatable(ManaBall, { __index = BaseSkill })

function ManaBall.new(casterId, data)
	local self = BaseSkill.new(casterId, data)
	setmetatable(self, ManaBall)
	return self
end

function ManaBall:use(requestData: any?)
	local req = requestData or {}
	-- We no longer send Instances to clients. Use the template key string that clients will use
	-- to acquire a pooled visual under ReplicatedStorage.Assets.Projectiles[templateKey].
	local templateKey = "ManaBall"

	local timing = self:resolveTiming()

	req.timing = timing

	if not self:applyResourceCost(req) then
		return
	end

	local durationScale = timing.durationScale
	local executionDuration = self.config.baseDuration * durationScale

	self:beginExecution(executionDuration, {
		lockJump = true,
		allowChain = false,
		autoComplete = false,
		timing = timing,
		sessionId = requestData and requestData.sessionId or nil, -- Phase 3
	})

	-- spawn-and-hold: we attach the visual to the caster's hand and let the client
	-- play the release animation; the server will activate the projectile when
	-- the client requests it. We still provide an authoritative launchSpeed.
	local speed = 60

	-- Magic scaling resolved via SkillMediator
	local magicDmg = self:resolveStat(StatTypes.StaticStats.MagicDamage)

	ProjectileService.spawnProjectile({
		templateKey = templateKey,
		-- spawn attached to the caster's right hand; clients will resolve the exact CFrame
		attach = { ownerUserId = self.player.UserId or nil, partName = "FX_Hand_R" },
		skillName = "ManaBall",
		launchSpeed = speed,
		owner = self.caster,
		faction = EntityUtils.getFaction(self.caster),
		radius = 1.5, -- slightly thick (kept for collision behavior when activated)
		pierce = 1,
		-- tell clients which impact FX to play by key (clients map keys -> actual assets)
		extraData = { impactKey = "ManaBallImpact" },
		onHit = function(_proj, _hitPart, hitEntity, _result)
			-- hitEntity is a Model from ProjectileService
			-- Convert to entityId for damage application
			local targetEntityId = Registrar.getEntityId(hitEntity)
			if targetEntityId then
				CombatService.applyDamage(targetEntityId, magicDmg, self.casterId)
			else
				warn(`[ManaBall] Hit entity {hitEntity.Name} has no entityId - skipping damage`)
			end
			return false -- stop after first hit
		end,
	})

	task.delay(durationScale, function()
		self:completeExecution()
	end)

	-- Return success response for client
	return {
		success = true,
		data = {
			duration = durationScale,
		},
	}
end

return ManaBall
