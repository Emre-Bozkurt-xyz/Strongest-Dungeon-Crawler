--!strict
-- Whether the local player's cast is currently blocked by a status effect (stun, silence, ...), as a
-- React binding -- shared across every slot on the bar the same way GCD is, since a blocked cast
-- blocks all of them, not one skill.
--
-- Ported from SkillSlotUI's blockedCastSources map: StatusEffectBlocking events name an effectId and
-- either open or close a window on it, and several effects can overlap (several stuns landing at
-- once), so what is shown is however long the longest-lived one still has. There is no guaranteed
-- "cleared" message for an effect that merely expires, which is why this runs a Heartbeat sweep
-- rather than trusting the event stream alone to know when to go blank.
--
-- Binding rather than state: `remaining` changes every visible frame while blocked, and this is
-- shared by every slot on the bar, so state here would reconcile the whole bar every tick.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local React = require(ReplicatedStorage.Packages.React)
local Networking = require(ReplicatedStorage.Shared.Networking)
local Registrar = require(script.Parent.Parent.Parent.Services.Registrar)

export type CastBlocked = {
	blocked: boolean,
	remaining: number?,
}

local NONE: CastBlocked = { blocked = false, remaining = nil }

local function useCastBlocked()
	local state, setState = React.useBinding(NONE)
	local sources = React.useRef({} :: { [string]: number })

	React.useEffect(function()
		local dispatcher = Networking.client() :: any
		dispatcher:_ensureChannel("StatusEffects")

		local offEvent = dispatcher:on("StatusEffectBlocking", function(payload: any, _meta: any?)
			if type(payload) ~= "table" then
				return
			end
			local localEntityId = Registrar.getLocalEntityId()
			if not localEntityId or payload.entityId ~= localEntityId then
				return
			end
			local action = payload.action
			if action ~= "cast" and action ~= "all" then
				return
			end

			local effectId = if type(payload.effectId) == "string" then payload.effectId else "unknown"
			if payload.blocked == true then
				local untilTime: number
				if type(payload.duration) == "number" then
					untilTime = os.clock() + payload.duration
				elseif type(payload.expiresAt) == "number" then
					untilTime = payload.expiresAt
				else
					untilTime = os.clock() + 9999
				end
				sources.current[effectId] = untilTime
			else
				sources.current[effectId] = nil
			end
		end)

		local heartbeat = RunService.Heartbeat:Connect(function()
			local now = os.clock()
			local longest: number? = nil
			for id, untilTime in pairs(sources.current) do
				if untilTime <= now then
					sources.current[id] = nil
				elseif not longest or untilTime > longest then
					longest = untilTime
				end
			end
			if longest then
				setState({ blocked = true, remaining = longest - now })
			else
				setState(NONE)
			end
		end)

		return function()
			offEvent()
			heartbeat:Disconnect()
		end
	end, {})

	return state
end

return useCastBlocked
