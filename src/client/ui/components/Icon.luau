--!strict
-- An image in an aspect-locked field.
--
-- The field keeps its shape regardless of the image, and ScaleType.Fit letterboxes anything with a
-- different native ratio. Items whose `icon` is empty render nothing rather than a broken-image box.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

local e = React.createElement

export type Props = {
	image: string?,
	-- Width / height of the field. 1 is square.
	ratio: number?,
	size: UDim2?,
	position: UDim2?,
	anchorPoint: Vector2?,
	layoutOrder: number?,
	color: Color3?,
	transparency: number?,
}

local function Icon(props: Props)
	return e("Frame", {
		Size = props.size or UDim2.fromScale(1, 1),
		Position = props.position or UDim2.fromScale(0.5, 0.5),
		AnchorPoint = props.anchorPoint or Vector2.new(0.5, 0.5),
		LayoutOrder = props.layoutOrder,
		BackgroundTransparency = 1,
	}, {
		Ratio = e("UIAspectRatioConstraint", {
			AspectRatio = props.ratio or 1,
			DominantAxis = Enum.DominantAxis.Height,
		}),
		Image = if props.image and props.image ~= ""
			then e("ImageLabel", {
				Image = props.image,
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				ImageColor3 = props.color,
				ImageTransparency = props.transparency,
				ScaleType = Enum.ScaleType.Fit,
			})
			else nil,
	})
end

return Icon
