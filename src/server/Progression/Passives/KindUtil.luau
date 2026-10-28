--!strict
-- Small helpers shared by passive kinds.

local KindTypes = require(script.Parent.KindTypes)

type Active = KindTypes.Active

local KindUtil = {}

-- The sum of `field` over `actives`, each scaled by its own growth.
function KindUtil.sum(actives: { Active }, field: string, accept: ((Active) -> boolean)?): number
	local total = 0
	for _, active in ipairs(actives) do
		local value = active.effect[field]
		if type(value) == "number" and (not accept or accept(active)) then
			total += value * active.scale
		end
	end
	return total
end

-- A per-key cooldown, for effects that must not fire more than once per moment: one swing reaching
-- several targets is one combo step, not several.
function KindUtil.cooldown(): (key: string, seconds: number) -> boolean
	local readyAt: { [string]: number } = {}
	local count = 0
	return function(key: string, seconds: number): boolean
		local now = os.clock()
		if (readyAt[key] or 0) > now then
			return false
		end
		if readyAt[key] == nil then
			count += 1
		end
		readyAt[key] = now + seconds
		-- Keys name targets, and targets come and go; expired ones are dropped now and then.
		if count > 256 then
			count = 0
			for other, time in pairs(readyAt) do
				if time <= now then
					readyAt[other] = nil
				else
					count += 1
				end
			end
		end
		return true
	end
end

return KindUtil
