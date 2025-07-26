local BaseSkill = require(script.Parent.BaseSkill)
local NetworkManager = require(script.Parent.Parent.Parent.NetworkManager)

local Punch = {}
Punch.__index = Punch

setmetatable(Punch, {
	__index = BaseSkill,
})

function Punch.new(player: Player, data: any)
	local self = BaseSkill.new(player, data)
	setmetatable(self, Punch)
	return self
end
function Punch:use()
	local physicalDamage = NetworkManager.invokeSignal("stats", {
		requestedStats = { "PhysicalDamage" },
		player = self.player,
	})
	if not physicalDamage then
		warn("Failed to retrieve physical damage for Punch skill")
		return
	end
	print(`Using Punch skill at level {self.level} with {physicalDamage} physical damage.`)
end
return Punch
