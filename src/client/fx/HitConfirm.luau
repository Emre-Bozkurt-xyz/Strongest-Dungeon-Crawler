--!strict
-- HitConfirm: a tick when one of the player's shots lands, from the server's HitEvent.
--
-- A melee blow is heard where it lands, next to the player (PredictedHits). A shot can land forty
-- studs away, where its impact is faint or out of sight, so the player gets a sound of their own:
-- not placed in the world, the same at any distance. Only for shots and their blasts, and only for
-- what an attack struck -- not a burn's ticks or a passive's damage.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Networking = require(ReplicatedStorage.Shared.Networking)
local Registrar = require(script.Parent.Parent.Services.Registrar)
local UISound = require(script.Parent.Parent.ui.UISound)

local HitConfirm = {}

local DELIVERIES: { [string]: boolean } = { projectile = true, area = true }
-- Seconds. A flurry of shots landing together (Cascading Mana Balls) ticks at this rate at most,
-- rather than as a buzz.
local MIN_INTERVAL = 0.09

local lastAt = -math.huge

function HitConfirm.init()
	Networking.client():on("HitEvent", function(event)
		if type(event) ~= "table" or event.sourceId ~= Registrar.getLocalEntityId() then
			return
		end
		if event.effectId ~= nil or event.skillId == "Passive" or not DELIVERIES[event.delivery] then
			return
		end
		local result = event.result or {}
		if result.dodged or (result.totalDamage or 0) <= 0 then
			return
		end
		local now = os.clock()
		if now - lastAt < MIN_INTERVAL then
			return
		end
		lastAt = now
		UISound.play(if result.crit then "hitConfirmCrit" else "hitConfirm")
	end)
end

return HitConfirm
