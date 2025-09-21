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
	elseif phase == "step" then
		local idx = (payload.step or 1) :: number
		-- Per-step body animation: prefer anim.comboSteps; fallback to legacy anim.impact string/table
		local stepAnims = spec.anim and spec.anim.comboSteps
		local legacyImpactAnim = (spec.anim and spec.anim.impact) --[[deprecated for animations]]
		if type(stepAnims) == "table" then
			local key = stepAnims[idx] or stepAnims[1]
			if key then
				AnimationPlayer.play(key)
			end
		elseif type(legacyImpactAnim) == "table" then
			local key = legacyImpactAnim[idx] or legacyImpactAnim[1]
			if key then
				AnimationPlayer.play(key)
			end
		elseif type(legacyImpactAnim) == "string" then
			AnimationPlayer.play(legacyImpactAnim)
		end
	elseif phase == "fx" then
		local idx = (payload.step or 1) :: number
		local anchor = payload.anchor
		local lifetime = payload.lifetime or 1
		local fxKeyOverride = payload.fxKey
		local resolvedFx: string? = fxKeyOverride
		if not resolvedFx then
			local impactFx = spec.fx and spec.fx.impact
			if type(impactFx) == "table" then
				resolvedFx = impactFx[idx] or impactFx[1]
			elseif type(impactFx) == "string" then
				resolvedFx = impactFx
			end
		end
		if not resolvedFx then
			return
		end
		local finalCFrame = payload.cframe or CFrame.new()
		if anchor and anchor.mode == "attachment" then
			local casterId = payload.casterId
			if casterId then
				local plr = game.Players:GetPlayerByUserId(casterId)
				local char = plr and plr.Character
				if char then
					local att = char:FindFirstChild(anchor.name, true)
					if att and att:IsA("Attachment") then
						FXPlayer.playAttached(resolvedFx, att, anchor.offset, lifetime)
						return
					end
					if anchor.fallback then
						local part = char:FindFirstChild(anchor.fallback)
						if part and part:IsA("BasePart") then
							finalCFrame = (part :: BasePart).CFrame
						end
					end
				end
			end
		end
		FXPlayer.playAt(resolvedFx, finalCFrame, lifetime)
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
