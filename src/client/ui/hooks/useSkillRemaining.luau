--!strict
-- Seconds remaining on a skill's own cooldown, as a React binding -- useSkillCooldown's sibling for
-- displays that need the actual countdown number (the timer label on a skill slot) rather than a
-- 0..1 fill ratio.
--
-- Kept as a separate hook rather than a second return value from useSkillCooldown: that hook is
-- scoped deliberately to "how full is the cooldown ring", and every existing call site destructures
-- a single binding -- growing its return shape would make call order load-bearing for a need only
-- one consumer (the timer label) has. The cost is a second Heartbeat connection per slot reading the
-- same SkillPacer snapshot; at up to five slots on the bar this is not worth avoiding.
--
-- Binding rather than state for the same reason as useSkillCooldown: the value differs every visible
-- frame.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local React = require(ReplicatedStorage.Packages.React)
local SkillPacer = require(script.Parent.Parent.Parent.SkillsFramework.SkillPacer)

-- nil when there is nothing to show, matching the old runtime's rule of only ever displaying a
-- number when one exists.
local function readRemaining(skillName: string): number?
	local snapshot = SkillPacer.getStateSnapshot(skillName)
	if not snapshot then
		return nil
	end

	local duration = snapshot.cooldownDuration
	if type(duration) ~= "number" or duration <= 0 then
		return nil
	end

	local startAt = snapshot.cooldownStartAt
	if type(startAt) ~= "number" then
		return nil
	end

	local remaining = (startAt + duration) - os.clock()
	if remaining <= 0 then
		return nil
	end
	return remaining
end

local function useSkillRemaining(skillName: string)
	local remaining, setRemaining = React.useBinding(nil :: number?)

	React.useEffect(function()
		local connection = RunService.Heartbeat:Connect(function()
			setRemaining(readRemaining(skillName))
		end)
		return function()
			connection:Disconnect()
		end
	end, { skillName })

	return remaining
end

return useSkillRemaining
