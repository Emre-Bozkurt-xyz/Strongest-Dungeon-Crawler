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
local AttachUtils = require(ReplicatedStorage.Shared.Projectiles.AttachUtils)
local SharedSpec = require(ReplicatedStorage.Shared.skills.Specs.ManaBall)

local ManaBall = {}
ManaBall.__index = ManaBall
setmetatable(ManaBall, { __index = BaseSkill })

local function mergeTables(base: any, override: any): any
	if type(base) ~= "table" and type(override) ~= "table" then
		return override ~= nil and override or base
	end
	local result = {}
	if type(base) == "table" then
		for k, v in pairs(base) do
			result[k] = v
		end
	end
	if type(override) == "table" then
		for k, v in pairs(override) do
			if type(v) == "table" and type(result[k]) == "table" then
				result[k] = mergeTables(result[k], v)
			else
				result[k] = v
			end
		end
	end
	return result
end

function ManaBall.new(casterId, data)
	local self = BaseSkill.new(casterId, data)
	setmetatable(self, ManaBall)
	return self
end

function ManaBall:use(requestData: any?)
	local req = requestData or {}
	local projectileCfg = mergeTables(SharedSpec.projectile, self.config.projectileServer)
	local templateKey = projectileCfg.templateKey or "ManaBall"

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
	local execToken = self:getExecutionToken()

	-- spawn-and-hold: we attach the visual to the caster's hand and let the client
	-- play the release animation; the server will activate the projectile when
	-- the client requests it. We still provide an authoritative launchSpeed.
	local attachPartName = AttachUtils.resolveAttachPartName(self.caster)
	local speed = projectileCfg.launchSpeed or 60

	-- Magic scaling resolved via SkillMediator
	local magicDmg = self:resolveStat(StatTypes.StaticStats.MagicDamage)

	ProjectileService.spawnProjectile({
		templateKey = templateKey,
		-- spawn attached to the caster's right hand; clients will resolve the exact CFrame
		attach = { ownerEntityId = self.casterId, partName = attachPartName, token = req.attemptId },
		skillName = "ManaBall",
		launchSpeed = speed,
		movementType = projectileCfg.movementType or "homing",
		guidance = projectileCfg.guidance,
		guidanceStack = projectileCfg.guidanceStack,
		owner = self.caster,
		faction = EntityUtils.getFaction(self.caster),
		radius = projectileCfg.radius,
		pierce = projectileCfg.pierce,
		lifetime = projectileCfg.lifetime,
		-- tell clients which impact FX to play by key (clients map keys -> actual assets)
		extraData = projectileCfg.extraData,
		onHit = function(_proj, _hitPart, hitEntity, _result)
			-- hitEntity is a Model from ProjectileService
			-- Convert to entityId for damage application
			local targetEntityId = Registrar.getEntityId(hitEntity)
			if targetEntityId then
				local attack = self:resolveAttack({
					damage = magicDmg,
					damageType = "Magic",
				})
				CombatService.applyAttack(targetEntityId, attack, self.casterId)
			else
				warn(`[ManaBall] Hit entity {hitEntity.Name} has no entityId - skipping damage`)
			end
			return false -- stop after first hit
		end,
	})

	self:guardedDelay(durationScale, function()
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
