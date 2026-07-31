--!strict
-- Global cooldown (GCD) progress, as a React binding -- the shared-across-skills counterpart to
-- useSkillCooldown.
--
-- GCD is not tracked per skill: SkillPacer starts it under the reserved "_GCD" key on CooldownClient
-- (see SkillPacer.refreshState calling CooldownClient.startLocal("_GCD", ...)), so any skill's
-- activation is gated by the same shared timer regardless of which skill started it. Reading through
-- CooldownClient rather than SkillPacer.getStateSnapshot(skillName) is what makes this shared rather
-- than per-skill -- SkillPacer's own per-skill state only records the GCD it last started, not
-- whether some other skill's GCD is still running.
--
-- Returns a binding for the same reason useSkillCooldown does: the value differs on every visible
-- frame, and writing it as state would reconcile every slot on the bar each tick instead of one
-- property on each.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local React = require(ReplicatedStorage.Packages.React)
local CooldownClient = require(script.Parent.Parent.Parent.SkillsFramework.CooldownClient)

local GCD_KEY = "_GCD"

-- 0 when ready, 1 when the GCD just started -- same convention as useSkillCooldown.
local function readProgress(): number
	local remaining = CooldownClient.getRemaining(GCD_KEY)
	if remaining <= 0 then
		return 0
	end
	local rec = CooldownClient.get(GCD_KEY)
	if not rec or rec.duration <= 0 then
		return 0
	end
	return math.clamp(remaining / rec.duration, 0, 1)
end

local function useGlobalCooldown()
	local progress, setProgress = React.useBinding(0)

	React.useEffect(function()
		local connection = RunService.Heartbeat:Connect(function()
			setProgress(readProgress())
		end)
		return function()
			connection:Disconnect()
		end
	end, {})

	return progress
end

return useGlobalCooldown
