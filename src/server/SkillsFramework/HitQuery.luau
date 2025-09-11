--!strict
-- Deprecated: Use server/skills/HitboxService instead.

local HitboxService = require(script.Parent.Parent:WaitForChild("skills"):WaitForChild("HitboxService"))

local HitQuery = {}

local function casterOriginCFrame(player: Player, yawOffsetDeg: number?): CFrame?
	local character = player.Character
	local hrp = character and (character:FindFirstChild("HumanoidRootPart") :: BasePart?)
	if not hrp then
		return nil
	end
	local yaw = math.rad(yawOffsetDeg or 0)
	return hrp.CFrame * CFrame.Angles(0, yaw, 0)
end

-- Maintains old signature returning only targets
function HitQuery.fromCasterCone(caster: Player, angleDeg: number, range: number, yawOffsetDeg: number?): { Model }
	warn("[HitQuery] deprecated. Use HitboxService.queryCone with an origin CFrame.")
	local cf = casterOriginCFrame(caster, yawOffsetDeg)
	if not cf then
		return {}
	end
	return HitboxService.queryCone(cf, angleDeg, range, { caster = caster, playersOnly = true })
end

return HitQuery
