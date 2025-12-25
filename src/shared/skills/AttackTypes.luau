--!strict
-- Attack Composition Types: Defines packet-based attack system for composable damage/effects

export type AttackPacketType = "damage" | "effect" | "heal" | "drain" | "knockback"

export type AttackPacket = {
	type: AttackPacketType,

	-- Damage packets
	damageType: string?, -- "Physical", "Fire", "Lightning", "Ice", "Poison", etc.
	amount: number?, -- Raw damage/heal amount
	penetration: number?, -- Armor penetration 0.0-1.0 (optional, for future use)

	-- Effect packets (status effects)
	effectId: string?, -- "Burn", "Wound", "Stun", "Slow", etc.
	chance: number?, -- Application chance 0.0-1.0 (nil = 100% chance)
	params: any?, -- Effect-specific parameters (power, duration, stacks, etc.)

	-- Heal/Drain packets
	poolType: string?, -- "HP", "Mana", "Stamina" (for heal/drain types)

	-- Knockback packets (future expansion)
	force: number?,
	direction: Vector3?,
}

export type AttackMetadata = {
	skillId: string?,
	tags: { string }?,
	isCrit: boolean?,
	comboStep: number?,
	-- Extensible: skills can add custom metadata fields
	[string]: any,
}

export type AttackContext = {
	packets: { AttackPacket },
	sourceId: string, -- entityId of attacker
	metadata: AttackMetadata,
}

return {}
