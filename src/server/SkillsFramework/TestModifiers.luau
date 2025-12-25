--!strict
-- Test module for demonstrating the modifier system
-- Exports a function that can be called after player fully spawns

local SampleModifiers = require(script.Parent.SampleModifiers)
local ModifierRegistry = require(script.Parent.ModifierRegistry)
local AttackResolver = require(script.Parent.AttackResolver)

local TestModifiers = {}

function TestModifiers.runTests(entityId: string)
	print(`\n=== Testing Modifiers on entity: {entityId} ===`)

	-- Clear any existing modifiers
	ModifierRegistry.clearEntity(entityId)

	-- Test 1: Fire Conversion Modifier
	print("\n=== Test 1: Fire Conversion (30% physical → fire) ===")
	SampleModifiers.createFireConversion(entityId)

	local ctx1 = {
		entityId = entityId,
		skillId = "Punch",
		queryType = "resolveAttack",
		tags = { "melee" },
		baseAttack = {
			damage = 100,
			damageType = "Physical",
			isCrit = false,
		},
	}

	local result1 = AttackResolver.resolve(ctx1)
	print("Packets:")
	for i, packet in ipairs(result1.packets) do
		print(`  {i}. Type={packet.type}, DamageType={packet.damageType or "N/A"}, Amount={packet.amount or 0}`)
	end
	-- Expected: 70 Physical + 30 Fire

	-- Test 2: Add Burn Effect
	print("\n=== Test 2: Fire Conversion + Burn Effect ===")
	SampleModifiers.createBurnOnFire(entityId)

	local result2 = AttackResolver.resolve(ctx1)
	print("Packets:")
	for i, packet in ipairs(result2.packets) do
		if packet.type == "effect" then
			print(`  {i}. Type={packet.type}, EffectId={packet.effectId}, Chance={packet.chance}`)
		else
			print(`  {i}. Type={packet.type}, DamageType={packet.damageType or "N/A"}, Amount={packet.amount or 0}`)
		end
	end
	-- Expected: 70 Physical + 30 Fire + Burn effect (30% chance)

	-- Test 3: Crit Multiplier
	print("\n=== Test 3: Critical Hit with 200% Multiplier ===")
	SampleModifiers.createCritMultiplier(entityId)

	local ctx3 = {
		entityId = entityId,
		skillId = "Punch",
		queryType = "resolveAttack",
		tags = { "melee" },
		baseAttack = {
			damage = 100,
			damageType = "Physical",
			isCrit = true, -- Critical hit
		},
	}

	local result3 = AttackResolver.resolve(ctx3)
	print("Packets:")
	for i, packet in ipairs(result3.packets) do
		if packet.type == "effect" then
			print(`  {i}. Type={packet.type}, EffectId={packet.effectId}, Chance={packet.chance}`)
		else
			print(`  {i}. Type={packet.type}, DamageType={packet.damageType or "N/A"}, Amount={packet.amount or 0}`)
		end
	end
	-- Expected: 140 Physical + 60 Fire + Burn (all doubled by crit)

	-- Test 4: Life Drain
	print("\n=== Test 4: Life Drain (15% of damage) ===")
	SampleModifiers.createLifeDrain(entityId)

	local result4 = AttackResolver.resolve(ctx3)
	print("Packets:")
	for i, packet in ipairs(result4.packets) do
		if packet.type == "effect" then
			print(`  {i}. Type={packet.type}, EffectId={packet.effectId}, Chance={packet.chance}`)
		elseif packet.type == "drain" then
			print(`  {i}. Type={packet.type}, PoolType={packet.poolType}, Amount={packet.amount}`)
		else
			print(`  {i}. Type={packet.type}, DamageType={packet.damageType or "N/A"}, Amount={packet.amount or 0}`)
		end
	end
	-- Expected: 140 Physical + 60 Fire + Burn + 30 Health drain (15% of 200 total damage)

	-- Test 5: Wound on Slash
	print("\n=== Test 5: Slash Attack with Bleed ===")
	SampleModifiers.createWoundOnSlash(entityId)

	local ctx5 = {
		entityId = entityId,
		skillId = "SlashAttack",
		queryType = "resolveAttack",
		tags = { "melee", "slash" },
		baseAttack = {
			damage = 100,
			damageType = "Physical",
			isCrit = false,
		},
	}

	local result5 = AttackResolver.resolve(ctx5)
	print("Packets:")
	for i, packet in ipairs(result5.packets) do
		if packet.type == "effect" then
			print(`  {i}. Type={packet.type}, EffectId={packet.effectId}, Chance={packet.chance}`)
		elseif packet.type == "drain" then
			print(`  {i}. Type={packet.type}, PoolType={packet.poolType}, Amount={packet.amount}`)
		else
			print(`  {i}. Type={packet.type}, DamageType={packet.damageType or "N/A"}, Amount={packet.amount or 0}`)
		end
	end
	-- Expected: 70 Physical + 30 Fire + Burn (30%) + Bleed (20%) + drain

	print("\n=== All Tests Complete ===")
	print("Registered modifiers:", #ModifierRegistry.getModifiers(entityId, "resolveAttack"))
end

return TestModifiers
