-- Builds placeholder KeyframeSequences for the R6 rig from the pose tables in Clips.luau.
--
-- Not synced by Rojo: this is Studio tooling, run by pasting into the command bar (or through the
-- Studio MCP) with both files as ModuleScripts under ServerStorage.AnimationRigs. Saves land in
-- ServerStorage.RBX_ANIMSAVES.AnimRig_R6 named by full clip key, which is where the Animation
-- Editor loads them for hand-polishing and where server/dev/AnimationDrafts finds them for
-- playtests.
--
--   local f = game.ServerStorage.AnimationRigs
--   local A = require(f.AnimAuthoring:Clone())
--   local holder = game.ServerStorage.RBX_ANIMSAVES.AnimRig_R6
--   for name, clip in require(f.Clips:Clone()) do
--       local old = holder:FindFirstChild(name) if old then old:Destroy() end
--       A.build(f.AnimRig_R6, name, clip).Parent = holder
--   end
--
-- Poses are written in the parent part's space (X right, Y up, -Z forward) as YXZ Euler degrees
-- plus an optional offset, and converted into each Motor6D's joint space here, so the clip tables
-- read as body movement rather than joint maths.

local M = {}

local rad = math.rad

local function partSpace(spec)
	local r = CFrame.fromEulerAnglesYXZ(rad(spec[1] or 0), rad(spec[2] or 0), rad(spec[3] or 0))
	if spec.offset then
		r = CFrame.new(spec.offset) * r
	end
	return r
end

-- Previews bake poses into C0 (see apply), so the rig's own C0 is kept as an attribute.
local function baseC0(motor)
	return motor:GetAttribute("BaseC0") or motor.C0
end

function M.toJoint(motor, spec)
	local c0r = baseC0(motor).Rotation
	return c0r:Inverse() * partSpace(spec) * c0r
end

function M.motors(rig)
	local out = {}
	for _, d in rig:GetDescendants() do
		if d:IsA("Motor6D") and d.Part1 then
			out[d.Part1.Name] = d
		end
	end
	return out
end

-- Poses a rig in place for a screenshot. Edit mode does not step Motor6D.Transform, so the pose is
-- baked into C0; call reset before building from the same rig.
function M.apply(rig, poses)
	for partName, motor in M.motors(rig) do
		if motor:GetAttribute("BaseC0") == nil then
			motor:SetAttribute("BaseC0", motor.C0)
		end
		local spec = poses[partName]
		motor.C0 = baseC0(motor) * (if spec then M.toJoint(motor, spec) else CFrame.identity)
	end
end

function M.reset(rig)
	for _, motor in M.motors(rig) do
		local b = motor:GetAttribute("BaseC0")
		if b then
			motor.C0 = b
			motor:SetAttribute("BaseC0", nil)
		end
	end
end

-- A pose's easing shapes the move from it to the next keyframe.
local EASE = {
	out = { Enum.PoseEasingStyle.Cubic, Enum.PoseEasingDirection.Out },
	inn = { Enum.PoseEasingStyle.Cubic, Enum.PoseEasingDirection.In },
	inout = { Enum.PoseEasingStyle.Cubic, Enum.PoseEasingDirection.InOut },
	linear = { Enum.PoseEasingStyle.Linear, Enum.PoseEasingDirection.In },
}

function M.build(rig, name, clip)
	local motors = M.motors(rig)
	local kfs = Instance.new("KeyframeSequence")
	kfs.Name = name
	kfs.Loop = clip.loop or false
	kfs.Priority = clip.priority or Enum.AnimationPriority.Action
	for _, key in clip.keys do
		local kf = Instance.new("Keyframe")
		kf.Time = key.t
		local root = Instance.new("Pose")
		root.Name = "HumanoidRootPart"
		root.Weight = 0
		root.Parent = kf
		local torsoPose = Instance.new("Pose")
		torsoPose.Name = "Torso"
		torsoPose.Parent = root
		local ease = EASE[key.ease or "inout"]
		local function setPose(pose, partName)
			pose.CFrame = M.toJoint(motors[partName], key.poses[partName] or {})
			pose.EasingStyle = ease[1]
			pose.EasingDirection = ease[2]
			pose.Weight = 1
		end
		setPose(torsoPose, "Torso")
		for _, partName in clip.parts do
			if partName ~= "Torso" then
				local p = Instance.new("Pose")
				p.Name = partName
				setPose(p, partName)
				p.Parent = torsoPose
			end
		end
		if key.marker then
			local m = Instance.new("KeyframeMarker")
			m.Name = key.marker
			m.Parent = kf
		end
		kf.Parent = kfs
	end
	return kfs
end

return M
