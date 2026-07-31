--!strict
-- Which skill the local player is currently executing, or nil.
--
-- Read from SessionMirror rather than inferred from cooldowns, because they answer different
-- questions. A cooldown starts when a skill is *committed* -- for a combo that is the first step, so
-- the cooldown is already counting down while the player is still mid-combo. "Am I using this right
-- now" is session state, and only the session knows about combo windows and held channels.
--
-- Sessions are event-driven, so this is state rather than a binding: it changes a handful of times
-- per cast, not per frame.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local SessionMirror = require(script.Parent.Parent.Parent.SkillsFramework.SessionMirror)

-- COMPLETED and CANCELLED are terminal: the session lingers briefly for correlation but the player
-- is no longer doing anything.
local function readActiveSkill(): string?
	local session = SessionMirror.getMySession()
	if not session then
		return nil
	end
	if session.state == "COMPLETED" or session.state == "CANCELLED" then
		return nil
	end
	return session.skillId
end

-- Sessions come and go across a predicted-to-authoritative handoff, and between combo steps, so the
-- live value drops to nil for a frame or two at moments when the player is very much still acting.
-- Releasing the active state is therefore delayed; acquiring it is not. Anything shorter than a
-- blink reads as a flicker, and a slightly late release reads as nothing at all.
local RELEASE_GRACE = 0.15

local function useActiveSkill(): string?
	local active, setActive = React.useState(readActiveSkill)
	local pending = React.useRef(nil :: thread?)

	React.useEffect(function()
		local function cancelPending()
			local thread = pending.current
			if thread then
				task.cancel(thread)
				pending.current = nil
			end
		end

		local function sync()
			local nextActive = readActiveSkill()
			if nextActive then
				cancelPending()
				setActive(nextActive)
				return
			end
			-- Already waiting to clear; let the existing timer run rather than restarting it.
			if pending.current then
				return
			end
			pending.current = task.delay(RELEASE_GRACE, function()
				pending.current = nil
				-- Re-read at fire time: a new session may have started during the grace period.
				setActive(readActiveSkill())
			end)
		end

		-- The callback's arguments are ignored and the mirror re-read: the payload describes one
		-- transition, while what is wanted is "what is live now" after it.
		local disconnect = SessionMirror.onStateChanged(sync)
		sync()

		return function()
			cancelPending()
			disconnect()
		end
	end, {})

	return active
end

return useActiveSkill
