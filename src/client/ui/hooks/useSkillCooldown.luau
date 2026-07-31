--!strict
-- Cooldown/GCD progress for a skill, as a React binding.
--
-- SkillPacer state is time-derived (`cooldownStartAt` + `cooldownDuration`), not event-driven, so
-- there is no "cooldown changed" moment to subscribe to -- the value is different on every frame it
-- is visible. A change signal would be the wrong abstraction, which is why SkillPacer never gained
-- one.
--
-- Returns a binding rather than state on purpose: updating a binding writes the property directly
-- without re-rendering the component. A sweep driven by useState would reconcile the whole subtree
-- every frame, for every skill on the bar.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local React = require(ReplicatedStorage.Packages.React)
local SkillPacer = require(script.Parent.Parent.Parent.SkillsFramework.SkillPacer)

-- 0 when ready, 1 when the cooldown just started.
local function readProgress(skillName: string): number
	local snapshot = SkillPacer.getStateSnapshot(skillName)
	if not snapshot then
		return 0
	end

	local duration = snapshot.cooldownDuration
	if type(duration) ~= "number" or duration <= 0 then
		return 0
	end

	local startAt = snapshot.cooldownStartAt
	if type(startAt) ~= "number" then
		return 0
	end

	local remaining = (startAt + duration) - os.clock()
	if remaining <= 0 then
		return 0
	end
	return math.clamp(remaining / duration, 0, 1)
end

local function useSkillCooldown(skillName: string)
	local progress, setProgress = React.useBinding(0)

	React.useEffect(function()
		local connection = RunService.Heartbeat:Connect(function()
			setProgress(readProgress(skillName))
		end)
		return function()
			connection:Disconnect()
		end
	end, { skillName })

	return progress
end

return useSkillCooldown
