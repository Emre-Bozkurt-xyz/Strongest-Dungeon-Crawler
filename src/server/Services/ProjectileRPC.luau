--!strict
-- Server-side RPC handlers for projectile intents (separated to avoid cyclic requires)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Networking = require(ReplicatedStorage.Shared.Networking)
local dispatcher = Networking.server()
local dispatcherAny = dispatcher :: any
dispatcherAny:_ensureChannel("Projectiles")

local ProjectileService = require(script.Parent.ProjectileService)

local DEFAULT_QOS = "HIGH"

-- Handle client RequestShoot intent: validate and activate attached projectile
dispatcherAny:on("RequestShoot", function(payload: any, meta: any)
	if type(payload) ~= "table" then
		return
	end
	local playerId = meta and meta.playerId
	if not playerId then
		return
	end
	local player = Players:GetPlayerByUserId(playerId)
	if not player then
		return
	end
	local projId = payload.projId
	if type(projId) ~= "number" then
		return
	end
	local proj = ProjectileService.getProjectile(projId)
	if not proj then
		dispatcherAny:intent(
			"RequestShootResponse",
			{ accepted = false, id = projId, reason = "not_found" },
			{ targets = player, qos = DEFAULT_QOS }
		)
		return
	end

	-- Ownership check
	local ownerOk = false
	if proj.owner and typeof(proj.owner) == "Instance" then
		local ok, isPlayer = pcall(function()
			return proj.owner:IsA("Player")
		end)
		if ok and isPlayer then
			ownerOk = (proj.owner :: any).UserId == player.UserId
		end
	end
	if not ownerOk then
		dispatcherAny:intent(
			"RequestShootResponse",
			{ accepted = false, id = projId, reason = "not_owner" },
			{ targets = player, qos = DEFAULT_QOS }
		)
		return
	end

	-- Timing window check (if supplied)
	local now = os.clock()
	if proj.attach and proj.attach.allowedWindow then
		local w = proj.attach.allowedWindow
		local start = w.start or -1e9
		local finish = w["end"] or (w.finish or 1e9)
		if not (now >= (start - 0.05) and now <= (finish + 0.12)) then
			dispatcherAny:intent(
				"RequestShootResponse",
				{ accepted = false, id = projId, reason = "bad_timing" },
				{ targets = player, qos = DEFAULT_QOS }
			)
			return
		end
	end

	-- Proximity sanity check
	local serverBone = nil
	if proj.attach and proj.attach.partName and player.Character then
		serverBone = player.Character:FindFirstChild(proj.attach.partName, true)
	end
	if serverBone and payload.localCFrame and payload.localCFrame.Position then
		local serverPos = nil
		if serverBone:IsA("Attachment") then
			serverPos = serverBone.WorldCFrame.Position
		elseif serverBone:IsA("BasePart") then
			serverPos = serverBone.Position
		end
		if serverPos then
			local dist = (serverPos - payload.localCFrame.Position).Magnitude
			if dist > 3 then
				dispatcherAny:intent(
					"RequestShootResponse",
					{ accepted = false, id = projId, reason = "bad_position" },
					{ targets = player, qos = DEFAULT_QOS }
				)
				return
			end
		end
	end

	-- Compute authoritative serverCFrame and velocity
	local serverCFrame = CFrame.new(proj.position)
	if serverBone then
		local offset = (proj.attach and proj.attach.offset) or CFrame.new()
		if serverBone:IsA("Attachment") then
			serverCFrame = serverBone.WorldCFrame * offset
		else
			serverCFrame = serverBone.CFrame * offset
		end
	end
	local speed = nil
	if proj.launchSpeed and type(proj.launchSpeed) == "number" then
		speed = proj.launchSpeed
	elseif payload.localVelocity and typeof(payload.localVelocity) == "Vector3" then
		speed = payload.localVelocity.Magnitude
	elseif proj.startVelocity and typeof(proj.startVelocity) == "Vector3" then
		speed = proj.startVelocity.Magnitude
	else
		speed = 30
	end
	local serverVelocity = serverCFrame.LookVector * speed

	local ok, reason = ProjectileService.activateAttachedProjectile(projId, serverCFrame, serverVelocity)

	dispatcherAny:intent("RequestShootResponse", {
		accepted = ok == true,
		id = projId,
		serverCFrame = serverCFrame,
		serverVelocity = serverVelocity,
		reason = reason,
	}, { targets = player, qos = DEFAULT_QOS })
end)

return true
