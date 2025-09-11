local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetRay = require(ReplicatedStorage.Packages.NetRay)

local AnimationPlayer = require(script.Parent.Parent.Parent.Client.fx.AnimationPlayer)
local FXPlayer = require(script.Parent.Parent.Parent.Client.fx.FXPlayer)
local ClientSpec = require(ReplicatedStorage.Shared.skills.ClientSpec)

local SkillsClient = {}

local request = NetRay:RegisterRequestEvent("SkillsRequest")
local event = NetRay:GetEvent("SkillsEvent")

local activeComboIdle: { [number]: string } = {}

event:OnEvent(function(payload)
	local phase = payload and payload.phase
	local id = payload and payload.id
	local spec = id and ClientSpec[id]
	if not phase or not id or not spec then
		return
	end
	if phase == "start" then
		local anim = spec.anim and spec.anim.start
		if type(anim) == "string" then
			AnimationPlayer.play(anim)
		elseif type(anim) == "table" then
			local k = anim[1]
			if k then
				AnimationPlayer.play(k)
			end
		end
	elseif phase == "impact" then
		local idx = (payload.step or 1) :: number
		local posCFrame = payload.cframe or CFrame.new()
		-- animations per impact optional
		local impactAnim = spec.anim and spec.anim.impact
		if type(impactAnim) == "table" then
			local key = impactAnim[idx] or impactAnim[1]
			if key then
				AnimationPlayer.play(key)
			end
		elseif type(impactAnim) == "string" then
			AnimationPlayer.play(impactAnim)
		end
		-- FX per impact
		local impactFx = spec.fx and spec.fx.impact
		if type(impactFx) == "table" then
			local fxKey = impactFx[idx] or impactFx[1]
			if fxKey then
				FXPlayer.playAt(fxKey, posCFrame)
			end
		elseif type(impactFx) == "string" then
			FXPlayer.playAt(impactFx, posCFrame)
		end
	elseif phase == "combo_wait" then
		local casterId = payload.casterId
		local open = payload.open
		local idleKey = spec.anim and spec.anim.comboIdle
		if open then
			if type(idleKey) == "string" then
				AnimationPlayer.play(idleKey)
				if casterId then
					activeComboIdle[casterId] = idleKey
				end
			end
		else
			if casterId and activeComboIdle[casterId] then
				AnimationPlayer.stop(activeComboIdle[casterId])
				activeComboIdle[casterId] = nil
			end
		end
	elseif phase == "end" or phase == "interrupt" then
		local finishAnim = spec.anim and spec.anim.finish
		if type(finishAnim) == "string" then
			AnimationPlayer.play(finishAnim)
		elseif type(finishAnim) == "table" then
			local k2 = finishAnim[1]
			if k2 then
				AnimationPlayer.play(k2)
			end
		end
	end
end)

function SkillsClient.useSkill(skillName: string)
	request:Request({ action = "use", skillName = skillName }):catch(function(err)
		warn("SkillsClient: Failed to request skill use:", err)
	end)
end

return SkillsClient
