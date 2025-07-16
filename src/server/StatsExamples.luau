--!strict
-- Example usage of the AttributesManager system
-- This script demonstrates various ways to interact with player attributes

local AttributesManager = require(script.Parent.AttributesManager)

local Examples = {}

-- Example 1: Level up system
function Examples.simulateLevelUp(player: Player)
	print(`Simulating level up for {player.Name}`)

	-- Give the player some attribute points
	AttributesManager.addToAttribute(player, "Strength", 2)
	AttributesManager.addToAttribute(player, "Intelligence", 1)
	AttributesManager.addToAttribute(player, "Vitality", 3)

	print(`Level up complete for {player.Name}`)
end

-- Example 2: Equipment system
function Examples.equipSword(player: Player)
	print(`Equipping sword for {player.Name}`)

	-- Add strength bonus from equipment
	AttributesManager.applyEquipmentBonus(player, "Strength", 15)
	-- Add dexterity bonus from equipment
	AttributesManager.applyEquipmentBonus(player, "Dexterity", 8)

	print(`Sword equipped for {player.Name}`)
end

function Examples.unequipSword(player: Player)
	print(`Unequipping sword for {player.Name}`)

	-- Remove strength bonus
	AttributesManager.removeEquipmentBonus(player, "Strength")
	-- Remove dexterity bonus
	AttributesManager.removeEquipmentBonus(player, "Dexterity")

	print(`Sword unequipped for {player.Name}`)
end

-- Example 3: Temporary buff system
function Examples.applyStrengthPotion(player: Player, duration: number?)
	duration = duration or 30 -- Default 30 seconds

	print(`Applying strength potion to {player.Name} for {duration} seconds`)

	-- Apply temporary strength bonus
	AttributesManager.applyEquipmentBonus(player, "Strength", 25)

	-- Remove the bonus after duration
	task.wait(duration)
	AttributesManager.removeEquipmentBonus(player, "Strength")

	print(`Strength potion wore off for {player.Name}`)
end

-- Example 4: Character creation/reset
function Examples.createNewCharacter(player: Player, characterClass: string)
	print(`Creating {characterClass} character for {player.Name}`)

	-- Reset to base attributes first
	AttributesManager.resetAttributes(player)

	-- Apply class-specific bonuses
	if characterClass == "Warrior" then
		AttributesManager.addToAttribute(player, "Strength", 10)
		AttributesManager.addToAttribute(player, "Vitality", 8)
		AttributesManager.addToAttribute(player, "Dexterity", 3)
	elseif characterClass == "Mage" then
		AttributesManager.addToAttribute(player, "Intelligence", 12)
		AttributesManager.addToAttribute(player, "Perception", 5)
		AttributesManager.addToAttribute(player, "Vitality", 2)
	elseif characterClass == "Rogue" then
		AttributesManager.addToAttribute(player, "Dexterity", 12)
		AttributesManager.addToAttribute(player, "Perception", 8)
		AttributesManager.addToAttribute(player, "Luck", 5)
	end

	print(`{characterClass} character created for {player.Name}`)
end

-- Example 5: Combat calculations using attributes
function Examples.calculateDamage(player: Player): number
	local strength = AttributesManager.getAttribute(player, "Strength") or 10
	local dexterity = AttributesManager.getAttribute(player, "Dexterity") or 10
	local luck = AttributesManager.getAttribute(player, "Luck") or 10

	-- Base damage calculation
	local baseDamage = strength * 2

	-- Critical hit chance based on dexterity and luck
	local critChance = (dexterity + luck) / 200 -- 1% per point
	local isCritical = math.random() < critChance

	local finalDamage = isCritical and baseDamage * 2 or baseDamage

	print(`{player.Name} deals {finalDamage} damage ${isCritical and "(CRITICAL!)" or ""}`)
	return finalDamage
end

-- Example 6: Attribute requirements check
function Examples.canUseItem(player: Player, requiredStrength: number, requiredIntelligence: number?): boolean
	local strength = AttributesManager.getAttribute(player, "Strength") or 0
	local intelligence = AttributesManager.getAttribute(player, "Intelligence") or 0

	requiredIntelligence = requiredIntelligence or 0

	local canUse = strength >= requiredStrength and intelligence >= (requiredIntelligence :: number)

	if not canUse then
		print(
			`{player.Name} cannot use item - requires {requiredStrength} Strength and {requiredIntelligence} Intelligence`
		)
	end

	return canUse
end

-- Example demo function that you can call to test everything
function Examples.runFullDemo(player: Player)
	print(`\n=== Running full attributes demo for {player.Name} ===`)

	-- 1. Create a warrior character
	Examples.createNewCharacter(player, "Warrior")
	task.wait(2)

	-- 2. Simulate leveling up
	Examples.simulateLevelUp(player)
	task.wait(2)

	-- 3. Equip a sword
	Examples.equipSword(player)
	task.wait(2)

	-- 4. Test damage calculation
	Examples.calculateDamage(player)
	task.wait(2)

	-- 5. Test item requirements
	Examples.canUseItem(player, 20, 5)
	task.wait(2)

	-- 6. Apply a temporary potion (in background)
	spawn(function()
		Examples.applyStrengthPotion(player, 10)
	end)

	task.wait(2)

	-- 7. Unequip sword
	Examples.unequipSword(player)

	print(`=== Demo complete for {player.Name} ===\n`)
end

return Examples
