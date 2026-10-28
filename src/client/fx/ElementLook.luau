--!strict
-- How an infused effect looks: the weapon's own projectile and impact templates, recoloured to the
-- element and resized for a named combination (progression-direction.md, "Forms": under the
-- generic rule "the effects take its colour").
--
-- Recolouring existing templates rather than authoring one per element keeps every shape working
-- with every element from day one; a named combination that needs a truly different look can still
-- name its own template.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MasteryTracks = require(ReplicatedStorage.Shared.progression.MasteryTracks)

export type Look = {
	color: Color3?,
	scale: number?,
	-- Distinguishes pooled instances: a recoloured clone must never come back as a plain one.
	key: string,
}

local ElementLook = {}

-- The colour an element's effects take, if the damage type is an element.
function ElementLook.colorOf(element: string?): Color3?
	local track = if element then MasteryTracks.forDamageType(element) else nil
	return if track then track.color else nil
end

-- The look a projectile's `extraData` asks for (`element`, `scale`, `impactScale`; set by the
-- server's BasicAttack), for the projectile itself or for its `impact`, or nil for the template as
-- authored.
function ElementLook.fromExtraData(extraData: any, impact: boolean?): Look?
	if type(extraData) ~= "table" then
		return nil
	end
	local element = if type(extraData.element) == "string" then extraData.element else nil
	local color = ElementLook.colorOf(element)
	local requested = if impact then extraData.impactScale or extraData.scale else extraData.scale
	local scale = if type(requested) == "number" and requested > 0 and requested ~= 1 then requested else nil
	if not color and not scale then
		return nil
	end
	return { color = color, scale = scale, key = `|{element or ""}|{scale or 1}` }
end

local function scaleSequence(sequence: NumberSequence, factor: number): NumberSequence
	local points = {}
	for _, point in ipairs(sequence.Keypoints) do
		table.insert(points, NumberSequenceKeypoint.new(point.Time, point.Value * factor, point.Envelope * factor))
	end
	return NumberSequence.new(points)
end

local function recolor(inst: Instance, color: Color3)
	if inst:IsA("BasePart") then
		inst.Color = color
	elseif inst:IsA("ParticleEmitter") then
		inst.Color = ColorSequence.new(color)
	elseif inst:IsA("Trail") then
		inst.Color = ColorSequence.new(color)
	elseif inst:IsA("Beam") then
		inst.Color = ColorSequence.new(color)
	elseif inst:IsA("Light") then
		inst.Color = color
	end
end

-- Apply `look` to a freshly cloned effect, in place. A model is resized as a whole (ScaleTo keeps
-- its welded parts and effects together); a single part's particles are resized directly, since
-- the part itself is an invisible anchor.
function ElementLook.apply(inst: Instance, look: Look?)
	if not look then
		return
	end
	local color = look.color
	if color then
		recolor(inst, color)
		for _, descendant in ipairs(inst:GetDescendants()) do
			recolor(descendant, color)
		end
	end
	local scale = look.scale
	if scale then
		if inst:IsA("Model") then
			inst:ScaleTo(inst:GetScale() * scale)
		else
			for _, descendant in ipairs(inst:GetDescendants()) do
				if descendant:IsA("ParticleEmitter") then
					descendant.Size = scaleSequence(descendant.Size, scale)
					descendant.Speed = NumberRange.new(descendant.Speed.Min * scale, descendant.Speed.Max * scale)
				end
			end
		end
	end
end

return ElementLook
