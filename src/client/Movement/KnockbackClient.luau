--!strict
-- KnockbackClient: pushes the local player's character when the server reports knockback on them.
--
-- A player owns their character's physics, so a mover placed by the server would lag behind and
-- fight the client's own simulation. The server resolves the push (who, which way, how far) and
-- carries it on HitEvent; the owning client plays it through the same mover as a dash.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Networking = require(ReplicatedStorage.Shared.Networking)
local MovementSpec = require(ReplicatedStorage.Shared.Movement.MovementSpec)
local Clock = require(ReplicatedStorage.Shared.Time.Clock)
local Registrar = require(script.Parent.Parent.Services.Registrar)
local MovementController = require(script.Parent.MovementController)

local KnockbackClient = {}

function KnockbackClient.init()
	local dispatcher = Networking.client()

	dispatcher:on("HitEvent", function(event)
		local result = event and event.result
		local knockback = result and result.knockback
		if type(knockback) ~= "table" then
			return
		end
		if typeof(knockback.direction) ~= "Vector3" or type(knockback.distance) ~= "number" then
			return
		end
		if event.targetId ~= Registrar.getLocalEntityId() then
			return
		end

		MovementController.startLocalDash(MovementSpec.buildKnockbackSpec({
			startTime = Clock.serverNow(),
			direction = knockback.direction,
			distance = knockback.distance,
			duration = if type(knockback.duration) == "number" then knockback.duration else nil,
		}))
	end)
end

return KnockbackClient
