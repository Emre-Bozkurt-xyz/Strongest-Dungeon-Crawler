--!strict

local TweenService = game:GetService("TweenService")

local WorldPanelVisibilityAnimator = {}

function WorldPanelVisibilityAnimator.playReplace(tweenMap: { [Instance]: Tween }, inst: Instance, info: TweenInfo, props: { [string]: any })
	local existing = tweenMap[inst]
	if existing then
		pcall(function()
			existing:Cancel()
		end)
	end
	local tween = TweenService:Create(inst, info, props)
	tweenMap[inst] = tween
	tween.Completed:Connect(function()
		if tweenMap[inst] == tween then
			tweenMap[inst] = nil
		end
	end)
	tween:Play()
	return tween
end

return WorldPanelVisibilityAnimator