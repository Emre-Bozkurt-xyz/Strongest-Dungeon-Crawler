--!strict

local WorldPanelFollower = {}

function WorldPanelFollower.computeYawAxes(root: BasePart): (Vector3, Vector3, Vector3)
	local forward = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	if forward.Magnitude <= 1e-4 then
		forward = Vector3.new(0, 0, -1)
	else
		forward = forward.Unit
	end
	local up = Vector3.yAxis
	local right = forward:Cross(up)
	if right.Magnitude <= 1e-4 then
		right = Vector3.new(1, 0, 0)
	else
		right = right.Unit
	end
	return right, up, forward
end

return WorldPanelFollower