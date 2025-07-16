--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- Testing systems

local AttributeTypes = require(ReplicatedStorage.Shared.AttributeTypes)
local StatTypes = require(ReplicatedStorage.Shared.StatTypes)
local StatsManager = require(script.Parent.StatsManager)
local AttributesManager = require(script.Parent.AttributesManager)

local Testing = {}

function Testing.runAllTests(player: Player)
	-- Here you would run all your tests

	StatsManager.setBaseStat(player, StatTypes.PoolStats.Mana, 150)
	print("Set base Mana to 150 for", player.Name)
	AttributesManager.addToAttribute(player, AttributeTypes.Attributes.Intelligence, 11)
	print("Added 10 Intelligence to", player.Name)
	local manaStat = StatsManager.getStat(player, StatTypes.PoolStats.Mana)
	if manaStat then
		print("Mana stat:", manaStat)
		print("Current Mana:", manaStat:getValue())
	else
		print("Mana stat not found for", player.Name)
	end

	local magicDamageStat = StatsManager.getStat(player, StatTypes.StaticStats.MagicDamage)
	if magicDamageStat then
		print("Magic damage stat:", magicDamageStat)
		print("New Magic Damage:", magicDamageStat:getValue())
	else
		print("Magic Damage stat not found for", player.Name)
	end
end

return Testing
