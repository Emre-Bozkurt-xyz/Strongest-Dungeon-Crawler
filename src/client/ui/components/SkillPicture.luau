--!strict
-- A skill's picture (selectors/skillLook): its mastery art where it exists, else its line glyph.
-- Drawn the same in the HUD's bar and the Loadout, so a skill reads as one thing in both.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local MasteryArt = require(ReplicatedStorage.Shared.progression.MasteryArt)

local Glyph = require(script.Parent.Glyph)
local skillLook = require(script.Parent.Parent.selectors.skillLook)

local e = React.createElement

export type Props = {
	look: skillLook.Look,
	-- Pixels, or a size in scale when the picture fills its parent.
	size: number | UDim2,
	-- A Color3, or a binding of one (the HUD dims it while the skill cools down).
	color: any,
	position: UDim2?,
	anchorPoint: Vector2?,
	zIndex: number?,
}

local function SkillPicture(props: Props)
	local size = if typeof(props.size) == "UDim2" then props.size else UDim2.fromOffset(props.size, props.size)
	local position = props.position or UDim2.fromScale(0.5, 0.5)
	local anchorPoint = props.anchorPoint or Vector2.new(0.5, 0.5)
	local art = if props.look.art then MasteryArt.get(props.look.art) else nil
	if art then
		local imageProps = MasteryArt.imageProps(art)
		imageProps.Size = size
		imageProps.Position = position
		imageProps.AnchorPoint = anchorPoint
		imageProps.BackgroundTransparency = 1
		imageProps.ImageColor3 = props.color
		imageProps.ScaleType = Enum.ScaleType.Fit
		imageProps.ZIndex = props.zIndex
		return e("ImageLabel", imageProps)
	end
	-- Line art fills its square edge to edge; drawn a little smaller to sit like the art does.
	return e("Frame", {
		Size = size,
		Position = position,
		AnchorPoint = anchorPoint,
		BackgroundTransparency = 1,
		ZIndex = props.zIndex,
	}, {
		Glyph = e(Glyph, {
			glyph = props.look.glyph,
			color = props.color,
			size = UDim2.fromScale(0.9, 0.9),
			position = UDim2.fromScale(0.5, 0.5),
			anchorPoint = Vector2.new(0.5, 0.5),
			zIndex = props.zIndex,
		}),
	})
end

return SkillPicture
