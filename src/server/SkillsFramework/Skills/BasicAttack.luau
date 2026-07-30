--!strict
-- Adaptive basic attack (Phase B, D6 in docs/tasks/equipment-item-architecture.md).
--
-- Filename must equal the skill name ("BasicAttack") -- SkillsConfig.addSkill does
-- require(SkillsFolder:WaitForChild(name)), unlike the client, which resolves its class from
-- spec.class instead (see trap 1 in the Phase B handoff brief).
--
-- Resolves the same BasicAttackProfileRegistry entry the client resolves, from the same
-- CombatLoadoutService source, so the combo step count/timing/animation/damage the server executes
-- always matches what the client already predicted (trap 4: do not reimplement resolution here).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Server = game:GetService("ServerScriptService").Server

local BaseComboSkill = require(script.Parent.BaseComboSkill)
local HitboxService = require(script.Parent.Parent.HitboxService)
local CombatService = require(Server.Services.CombatService)
local CombatLoadoutService = require(Server.Inventory.CombatLoadout.CombatLoadoutService)
local EquipmentVisualService = require(Server.Inventory.EquipmentVisualService)
local ProjectileService = require(Server.Services.ProjectileService)
local Registrar = require(Server.Services.Registrar)
local BasicAttackProfileRegistry = require(ReplicatedStorage.Shared.skills.BasicAttackProfileRegistry)
local BasicAttackProfileTypes = require(ReplicatedStorage.Shared.skills.BasicAttackProfileTypes)
local HandResolver = require(ReplicatedStorage.Shared.skills.HandResolver)
local ItemTypes = require(ReplicatedStorage.Shared.items.ItemTypes)
local EntityUtils = require(ReplicatedStorage.Shared.EntityUtils)
local AttackResolver = require(script.Parent.Parent.AttackResolver)
local DebugConfig = require(ReplicatedStorage.Shared.Debug.DebugConfig)

-- `both` never appears here; projectile steps resolve a single concrete hand.
local SLOT_BY_HAND: { [string]: string } = {
	main = "Main",
	secondary = "Secondary",
}

-- How long the server will wait for a client to report a step's release marker before firing the
-- projectile anyway. A bound on client trust rather than a tuning value: it caps how long a stalling
-- or silent client can defer a shot. Long enough to cover a marker late in a cast animation plus
-- round-trip latency.
local MARKER_RELEASE_TIMEOUT = 0.6

local BasicAttack = {}
BasicAttack.__index = BasicAttack

setmetatable(BasicAttack, { __index = BaseComboSkill })

local function logFlow(...: any)
	if DebugConfig.isEnabled("inputFlow") then
		print("[InputFlow]", ...)
	end
end

function BasicAttack.new(casterId: string, data: any)
	local self = BaseComboSkill.new(casterId, data)
	setmetatable(self, BasicAttack)
	self._activeProfile = nil :: BasicAttackProfileTypes.BasicAttackProfile?
	-- Held from activation so a projectile fired partway through the animation uses the aim from when
	-- the button was pressed, not wherever the camera has swung during the wind-up.
	self._aimRequestData = nil :: any
	-- Marker-release handshake state. `_markerAhead` exists because the client's marker request can
	-- arrive before the server has run the step it belongs to; without it that early marker would be
	-- dropped and the shot would wait out the full timeout instead.
	self._pendingRelease = nil :: any
	self._markerAheadStep = nil :: number?
	-- D9: per-caster alternation cursor. Reset at the start of every combo in :use() below, which
	-- also covers trap 4's "reset on weapon swap/death/respawn" -- see HandResolver's doc comment.
	self._handAlternation = HandResolver.newAlternationState()
	return self
end

local function casterOriginCFrame(skill: any): CFrame?
	local root = skill:getCasterRootPart()
	if not root then
		return nil
	end
	return root.CFrame
end

function BasicAttack:use(requestData: any?): any
	-- Resolve before delegating: BaseComboSkill:use() reads self.config.combo for step
	-- count/timing, so it must already reflect the current loadout's profile by the time it runs.
	local loadout = CombatLoadoutService.get(self.casterId)
	local profile = BasicAttackProfileRegistry.resolve(loadout)
	self._activeProfile = profile
	self.config.combo = profile.combo

	-- onComboStep runs later on a hit delay and receives no request data of its own.
	self._aimRequestData = requestData

	-- A marker reported against the previous step must not release this one.
	self._pendingRelease = nil
	self._markerAheadStep = nil

	-- D9: alternation resets at the start of every combo (not persisted across chains), so the
	-- same input always produces the same hand sequence. `isNewChain` is set by SkillsManager
	-- before this runs.
	local comboInfo = requestData and requestData.combo
	if not comboInfo or comboInfo.isNewChain then
		self._handAlternation = HandResolver.newAlternationState()
	end

	logFlow(`BasicAttack:use caster={self.casterId} resolved profile='{profile.id}'`)
	return BaseComboSkill.use(self, requestData)
end

-- Sweep the profile's hit cone and apply `damages` to everything in it. Also where a projectile
-- step lands when its weapon declares no projectile.
function BasicAttack:applyConeStep(step: number, coneAngle: number, coneRange: number, damages: { AttackResolver.TypedDamage })
	local origin = casterOriginCFrame(self)
	if not origin then
		return
	end

	local targets = HitboxService.newQuery(origin)
		:casterEntityId(self.casterId)
		:factionRelation("enemy")
		:playersOnly(false)
		:cone(coneAngle, coneRange)
		:collect({ collectIds = true, debug = true })

	local targetIds = targets.ids
	if not targetIds then
		return
	end

	local attack = self:resolveAttack({
		damages = damages,
		comboStep = step,
	})

	for _, targetEntityId in ipairs(targetIds) do
		CombatService.applyAttack(targetEntityId, attack, self.casterId)
	end
end

-- Fire the equipped weapon's projectile, carrying this step's already-scaled typed damage.
--
-- The weapon owns the projectile's identity and flight; this step only decided that one is fired
-- (BasicAttackDelivery). Because `damages` arrives already typed and already scaled, a flame wand
-- needs no code here at all -- it declares Fire damage and a FireBolt template on the item and
-- both flow through untouched. That is the whole point of the weapon/profile split.
--
-- Returns false when the projectile cannot be fired, so the caller can fall back to a cone rather
-- than the step silently doing nothing.
function BasicAttack:fireProjectileStep(
	step: number,
	hand: string,
	projectile: ItemTypes.WeaponProjectileConfig,
	damages: { AttackResolver.TypedDamage }
): boolean
	-- Position only. The attachment's orientation is whatever the artist gave it, rotated by whatever
	-- the animation is doing this frame -- useless as an aim vector.
	local slot = SLOT_BY_HAND[hand]
	local muzzle = if slot then EquipmentVisualService.getSocketCFrame(self.casterId, slot, projectile.muzzleSocket) else nil
	if not muzzle then
		warn(
			`[BasicAttack] Weapon in {tostring(slot)} declares muzzleSocket '{projectile.muzzleSocket}' but no such`
				.. ` Attachment exists on its equipped visual; falling back to a cone hit for this step.`
				.. ` (EquipmentAuthoringValidator checks this at startup -- the asset is likely missing the attachment.)`
		)
		return false
	end

	local origin = muzzle.Position

	-- Resolved from the muzzle, not the camera: the muzzle sits most of a character's width off the
	-- camera axis, so a bolt fired parallel to the camera ray drifts wider the further it travels
	-- and misses what the cursor was over. Aiming muzzle->point converges at every range.
	--
	-- No aim falls back to the caster's facing, which is what NPCs want since they turn to face
	-- their target.
	local direction = self:resolveAimDirection(self._aimRequestData, origin)
	if not direction then
		local root = self:getCasterRootPart()
		if not root then
			return false
		end
		direction = root.CFrame.LookVector
	end

	local speed = projectile.launchSpeed
	local movementType = projectile.movementType or "linear"

	-- Guidance is only meaningful for homing movement; passing it otherwise makes
	-- ProjectileService acquire a target it will never steer toward.
	local guidance: any = nil
	if movementType == "homing" then
		local homing = projectile.homing
		guidance = {
			kind = "homing",
			turnRate = homing and homing.turnRate or nil,
			maxRange = homing and homing.maxRange or nil,
			reacquire = homing and homing.reacquire or nil,
			factionRelation = "enemy",
		}
	end

	ProjectileService.spawnProjectile({
		templateKey = projectile.templateKey,
		skillName = "BasicAttack",
		-- From the aim direction rather than `muzzle`, so orientation matches the velocity the
		-- client simulates.
		cframe = CFrame.lookAt(origin, origin + direction),
		velocity = direction * speed,
		launchSpeed = speed,
		movementType = movementType,
		gravity = projectile.gravity,
		lifetime = projectile.lifetime,
		radius = projectile.radius,
		pierce = projectile.pierce,
		guidance = guidance,
		extraData = projectile.extraData,
		owner = self.caster,
		faction = EntityUtils.getFaction(self.caster :: Model),
		onHit = function(_proj, _hitPart, hitEntity, _result)
			local targetEntityId = Registrar.getEntityId(hitEntity)
			if not targetEntityId then
				warn(`[BasicAttack] Projectile hit '{hitEntity.Name}' which has no entityId - skipping damage`)
				return false
			end
			-- Resolved at hit time so crit rolls reflect the moment of impact, not of firing.
			local attack = self:resolveAttack({
				damages = damages,
				comboStep = step,
			})
			CombatService.applyAttack(targetEntityId, attack, self.casterId)
			-- Stop on first hit unless the weapon authored pierce.
			return false
		end,
	})

	return true
end

-- Hold `fire` until the client reports this step's release marker, or until the timeout, whichever
-- comes first. Exactly one of those wins; the loser is a no-op.
function BasicAttack:armMarkerRelease(step: number, fire: () -> ())
	if self._markerAheadStep == step then
		self._markerAheadStep = nil
		fire()
		return
	end

	local pending = { step = step, fire = fire, fired = false }
	self._pendingRelease = pending

	task.delay(MARKER_RELEASE_TIMEOUT, function()
		if pending.fired or self._pendingRelease ~= pending then
			return
		end
		pending.fired = true
		self._pendingRelease = nil
		logFlow(`BasicAttack:armMarkerRelease timed out caster={self.casterId} step={step}`)
		fire()
	end)
end

-- SkillRequestMarker handler (dispatched by SkillsManager). Returning a table counts as success.
function BasicAttack:onReleaseMarker(requestData: any?): (any?, string?)
	local step = requestData and requestData.comboStep
	if type(step) ~= "number" then
		return nil, "missing_combo_step"
	end

	local pending = self._pendingRelease
	if pending and pending.step == step and not pending.fired then
		pending.fired = true
		self._pendingRelease = nil
		logFlow(`BasicAttack:onReleaseMarker caster={self.casterId} step={step}`)
		pending.fire()
		return { released = true }
	end

	-- The marker beat the step it belongs to; onComboStep will consume this on arrival.
	self._markerAheadStep = step
	return { released = false }
end

function BasicAttack:onComboStep(step: number)
	-- Defensive fallback: onComboStep should only ever run after use() has set _activeProfile, but
	-- if something ever calls it without going through use() first, fail loud-but-safe rather than
	-- indexing into a nil profile.
	local profile = self._activeProfile
	if not profile then
		warn("BasicAttack:onComboStep called with no resolved profile; falling back to unarmed_basic")
		profile = BasicAttackProfileRegistry.getUnarmedProfile()
		self._activeProfile = profile
	end

	local stepSpec = profile.steps[step] or profile.steps[#profile.steps]
	local mult = stepSpec.damageMultiplier
	local coneAngle = stepSpec.coneAngle or profile.hitCone.angle
	local coneRange = stepSpec.coneRange or profile.hitCone.range

	-- D9: resolve which hand actually swings this step. An authored hand on the step always wins;
	-- otherwise HandResolver alternates between both hands when dual-wielding one-handed weapons,
	-- resetting each combo (never reimplemented here -- see HandResolver's own doc comment).
	local loadout = CombatLoadoutService.get(self.casterId)
	local hand = HandResolver.resolveHand(stepSpec.hand, loadout, self._handAlternation)
	logFlow(`BasicAttack:onComboStep caster={self.casterId} step={step} hand={hand}`)

	-- Weapon-scoped affix bonuses are already folded into the loadout's weapon damage ranges by
	-- CombatLoadoutResolver; the type-matched global flat damage stat is added on top (D2).
	-- The weapon's own damage types are carried through, so a wand deals Magic and a flame wand
	-- deals Fire rather than everything being flattened to Physical. `hand = "both"` concatenates
	-- both hands' typed damage lists (see BaseSkill:resolveWeaponDamage) rather than picking one --
	-- the natural reading of "this step intentionally uses both hands" (trap 6).
	local damages: { AttackResolver.TypedDamage } = self:resolveWeaponDamage(hand)
	local scaled: { AttackResolver.TypedDamage } = {}
	for _, entry in ipairs(damages) do
		table.insert(scaled, { type = entry.type, amount = entry.amount * mult })
	end

	-- Delivery decides how the damage reaches a target; it never changes what the damage *is*.
	-- Both paths receive the identical `scaled` list, which is why a flame wand needs no code here.
	if (stepSpec.delivery or "cone") == "projectile" then
		local weapon = self:getLoadoutWeapon(hand)
		local projectile = weapon and weapon.projectile or nil
		if projectile then
			-- A step naming a release marker defers the shot to the animation; one without fires on
			-- the authored hit delay, which is this call.
			if stepSpec.releaseMarker then
				self:armMarkerRelease(step, function()
					if not self:fireProjectileStep(step, hand, projectile, scaled) then
						self:applyConeStep(step, coneAngle, coneRange, scaled)
					end
				end)
				return
			end
			if self:fireProjectileStep(step, hand, projectile, scaled) then
				return
			end
			-- fireProjectileStep already warned; fall through to the cone below.
		else
			-- Loud fallback rather than a step that quietly does nothing (trap 5). The validator
			-- rejects this pairing at startup, so reaching it means a weapon was equipped whose
			-- profile was resolved by weapon *class* rather than by an explicit id.
			warn(
				`[BasicAttack] Profile '{profile.id}' step {step} is projectile-delivery but the weapon in`
					.. ` {tostring(SLOT_BY_HAND[hand])} ('{weapon and weapon.itemId or "none"}') declares no`
					.. ` projectile; falling back to a cone hit.`
			)
		end
	end

	self:applyConeStep(step, coneAngle, coneRange, scaled)
end

return BasicAttack
