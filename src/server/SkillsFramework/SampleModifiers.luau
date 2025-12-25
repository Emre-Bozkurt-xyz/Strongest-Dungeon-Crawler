--!strict
-- Sample attack modifiers demonstrating the modifier system
-- These can be applied to entities via ModifierRegistry

local ModifierRegistry = require(script.Parent.ModifierRegistry)

local SampleModifiers = {}

-- Fire Conversion Modifier: Convert 30% of physical damage to fire
function SampleModifiers.createFireConversion(entityId: string)
	ModifierRegistry.register(entityId, "resolveAttack", {
		id = "fire_conversion",
		priority = 50, -- Mid priority
		matches = function(ctx)
			-- Apply to melee skills only
			return ctx.tags and table.find(ctx.tags, "melee") ~= nil
		end,
		apply = function(ctx, result)
			-- Find physical damage packets and convert 30% to fire
			for i, packet in ipairs(result.packets) do
				if packet.type == "damage" and packet.damageType == "Physical" then
					local physicalAmount = packet.amount or 0
					local fireAmount = physicalAmount * 0.3
					local remainingPhysical = physicalAmount * 0.7

					-- Update physical packet
					result.packets[i].amount = remainingPhysical

					-- Add fire packet
					table.insert(result.packets, {
						type = "damage",
						damageType = "Fire",
						amount = fireAmount,
					})
					break -- Only convert first physical packet
				end
			end
		end,
		source = "fire_enchantment",
	})
end

-- Burn Effect Modifier: 30% chance to apply Burn on fire damage
function SampleModifiers.createBurnOnFire(entityId: string)
	ModifierRegistry.register(entityId, "resolveAttack", {
		id = "burn_on_fire",
		priority = 100, -- Low priority (after damage conversion)
		matches = function(ctx)
			-- Always applies if fire damage exists
			return true
		end,
		apply = function(ctx, result)
			-- Check if any fire damage packets exist
			local hasFire = false
			for _, packet in ipairs(result.packets) do
				if packet.type == "damage" and packet.damageType == "Fire" then
					hasFire = true
					break
				end
			end

			if hasFire then
				-- Add Burn effect packet
				table.insert(result.packets, {
					type = "effect",
					effectId = "Burn",
					chance = 0.3,
					params = {
						duration = 5,
						tickDamage = 10,
					},
				})
			end
		end,
		source = "fire_mastery_passive",
	})
end

-- Crit Multiplier Modifier: Increase crit damage to 200%
function SampleModifiers.createCritMultiplier(entityId: string)
	ModifierRegistry.register(entityId, "resolveAttack", {
		id = "crit_multiplier",
		priority = 10, -- High priority (before other transformations)
		matches = function(ctx)
			-- Only applies on crits
			return ctx.baseAttack.isCrit == true
		end,
		apply = function(ctx, result)
			-- Multiply all damage packets by 2.0 (100% bonus)
			for i, packet in ipairs(result.packets) do
				if packet.type == "damage" and packet.amount then
					result.packets[i].amount = packet.amount * 2.0
				end
			end
		end,
		source = "critical_strike_talent",
	})
end

-- Wound Effect Modifier: Slash attacks have 20% chance to apply Bleed
function SampleModifiers.createWoundOnSlash(entityId: string)
	ModifierRegistry.register(entityId, "resolveAttack", {
		id = "wound_on_slash",
		priority = 100, -- Low priority
		matches = function(ctx)
			-- Apply to slash-tagged skills
			return ctx.tags and table.find(ctx.tags, "slash") ~= nil
		end,
		apply = function(ctx, result)
			-- Add Bleed effect packet
			table.insert(result.packets, {
				type = "effect",
				effectId = "Bleed",
				chance = 0.2,
				params = {
					duration = 6,
					tickDamage = 5,
				},
			})
		end,
		source = "bleed_mastery_passive",
	})
end

-- Life Drain Modifier: Heal for 15% of damage dealt
function SampleModifiers.createLifeDrain(entityId: string)
	ModifierRegistry.register(entityId, "resolveAttack", {
		id = "life_drain",
		priority = 200, -- Very low priority (after all damage calculations)
		matches = function(ctx)
			-- Always applies
			return true
		end,
		apply = function(ctx, result)
			-- Calculate total damage
			local totalDamage = 0
			for _, packet in ipairs(result.packets) do
				if packet.type == "damage" and packet.amount then
					totalDamage = totalDamage + packet.amount
				end
			end

			if totalDamage > 0 then
				-- Add heal packet for 15% of damage
				table.insert(result.packets, {
					type = "drain",
					poolType = "Health",
					amount = totalDamage * 0.15,
				})
			end
		end,
		source = "vampiric_aura",
	})
end

return SampleModifiers
