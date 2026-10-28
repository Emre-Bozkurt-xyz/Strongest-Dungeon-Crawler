--!strict
-- A burst in the element's colour on anything struck by element damage, from the server's HitEvent.
--
-- Projectiles already carry their element to their impact (ElementLook); this gives a melee form
-- the same read, so an infused punch looks infused. It reuses an existing impact template,
-- recoloured, rather than one authored per element.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Networking = require(ReplicatedStorage.Shared.Networking)
local Registrar = require(script.Parent.Parent.Services.Registrar)
local FXPlayer = require(script.Parent.FXPlayer)
local ElementLook = require(script.Parent.ElementLook)

local BURST_KEY = "ManaBallImpact"

local ElementHitFX = {}

local function onHit(event: any)
	local result = event and event.result
	if type(result) ~= "table" or type(result.byType) ~= "table" then
		return
	end
	local target = Registrar.getEntityById(event.targetId)
	local root = target and target:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	-- The largest element in the hit decides the colour; one burst per hit, not one per type.
	local element: string? = nil
	local largest = 0
	for damageType, amount in pairs(result.byType) do
		if type(amount) == "number" and amount > largest and ElementLook.colorOf(damageType) then
			element = damageType
			largest = amount
		end
	end
	if not element then
		return
	end
	FXPlayer.playAt(BURST_KEY, root.CFrame, nil, { color = ElementLook.colorOf(element), scale = 1.6, key = "" })
end

function ElementHitFX.init()
	Networking.client():on("HitEvent", onHit)
end

return ElementHitFX
