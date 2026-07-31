--!strict
-- One skill slot: icon, the shrinking cooldown ring, the faint global-cooldown wash, the blocked-cast
-- tint, its keybind, and the countdown number. Ported from SkillSlotContainer in
-- docs/ui/SkillSlotContainer.rbxmx.
--
-- Owns its own useSkillCooldown/useSkillRemaining calls so the number of hooks per render never
-- depends on how many slots the bar has -- each slot gets its own component precisely so its hooks
-- belong to it (StatusPreviewView documents the same discipline for a differently-shaped hazard: a
-- hook that must never become conditional on how much data is currently available).
--
-- GCD and cast-blocked are shared across every slot -- SkillSlots.activate gates on the same GCD key
-- and the same status effect no matter which slot fired it -- so those arrive as bindings computed
-- once by the container (useGlobalCooldown, useCastBlocked) and passed down as props, rather than one
-- redundant Heartbeat connection per slot for an identical shared value.
--
-- Two simplifications versus SkillSlotUI, both recorded in the panel's capability checklist rather
-- than silently dropped: the GCD wash shows whenever the GCD is running, even on a slot whose own
-- cooldown already outlasts it (the old runtime suppressed that redundant case); and there is no
-- MIN_VISUAL_DURATION filter on sub-0.33s combo-step cooldowns, because useSkillCooldown exposes only
-- a 0..1 ratio, not the raw duration such a filter needs.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ThemeContext = require(script.Parent.Parent.Parent.hooks.ThemeContext)
local useSkillCooldown = require(script.Parent.Parent.Parent.hooks.useSkillCooldown)
local useSkillRemaining = require(script.Parent.Parent.Parent.hooks.useSkillRemaining)
local SkillActions = require(script.Parent.Parent.Parent.actions.SkillActions)
local Selector = require(script.Parent.Parent.Parent.selectors.skillSlots)
local CooldownRadial = require(script.Parent.CooldownRadial)

local e = React.createElement

local BASE_TRANSPARENCY = 0.6

export type Props = {
	index: number,
	skill: string,
	icon: string,
	keyLabel: string?,
	layoutOrder: number,
	-- Bindings shared across the whole bar; see the header note above.
	gcdProgress: any,
	castBlocked: any,
	-- This skill is mid-execution: a combo between steps, or a channel being held.
	active: boolean?,
}

local function SkillSlotButton(props: Props)
	local theme = ThemeContext.useTheme()
	local cooldownProgress = useSkillCooldown(props.skill)
	local remaining = useSkillRemaining(props.skill)

	local joined = React.joinBindings({
		cooldown = cooldownProgress,
		gcd = props.gcdProgress,
	})

	local iconColor = joined:map(function(v)
		local locked = not active and (v.cooldown > 0 or v.gcd > 0)
		return if locked then theme.color.iconCooldownTint else theme.color.iconReadyTint
	end)

	-- Every "you cannot use this" visual is suppressed while the skill is running. A combo commits its
	-- cooldown on the first step, so without this the slot shows a countdown while the player is still
	-- swinging -- which is what the cooldown genuinely says, and exactly the wrong thing to show.
	local active = props.active == true

	local radialVisible = cooldownProgress:map(function(p)
		return not active and p > 0
	end)

	local gcdVisible = props.gcdProgress:map(function(p)
		return not active and p > 0
	end)

	local timerVisible = remaining:map(function(r)
		return not active and r ~= nil and r > 0 and r <= 10
	end)
	local timerText = remaining:map(function(r)
		return if r and r > 0 then Selector.formatTime(r) else ""
	end)

	local blockedVisible = props.castBlocked:map(function(v)
		return v.blocked
	end)

	return e("TextButton", {
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromOffset(60, 60),
		LayoutOrder = props.layoutOrder,
		BackgroundColor3 = if active then theme.color.skillSlotActiveStroke else theme.color.skillSlotSurface,
		BackgroundTransparency = if active then 0.55 else BASE_TRANSPARENCY,
		[React.Event.Activated] = function()
			SkillActions.activate(props.index)
		end,
	}, {
		Corner = e("UICorner", { CornerRadius = UDim.new(0, theme.metrics.radiusControl) }),
		-- Placeholder active treatment, but additive rather than another veil: the cooldown and GCD
		-- states both work by dimming, so anything that dims cannot read as "this is firing right
		-- now". Bright outline, warm wash, and the slot lifts out of the row.
		Stroke = e("UIStroke", {
			Color = if active then theme.color.skillSlotActiveStroke else theme.color.skillSlotStroke,
			Thickness = if active then 4 else 2.5,
			Transparency = if active then 0 else 0.17,
		}),
		Lift = if active
			then e("UIScale", { Scale = 1.12 })
			else nil,
		Glow = if active
			then e("UIStroke", {
				Color = theme.color.skillSlotActiveStroke,
				Thickness = 9,
				Transparency = 0.72,
			})
			else nil,

		Radial = e(CooldownRadial, {
			value = cooldownProgress,
			visible = radialVisible,
			baseColor = theme.color.skillSlotSurface,
			baseTransparency = BASE_TRANSPARENCY,
		}),

		Content = e("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 5,
		}, {
			Padding = e("UIPadding", {
				PaddingTop = UDim.new(0, 4),
				PaddingBottom = UDim.new(0, 4),
				PaddingLeft = UDim.new(0, 4),
				PaddingRight = UDim.new(0, 4),
			}),
			-- Renders nothing rather than a broken-image placeholder when a skill has no icon (R12
			-- improvement over the old fallback of "rbxassetid://0").
			Icon = if props.icon ~= ""
				then e("ImageLabel", {
					Image = props.icon,
					ScaleType = Enum.ScaleType.Stretch,
					BackgroundTransparency = 1,
					Size = UDim2.fromScale(1, 1),
					ImageColor3 = iconColor,
					ZIndex = 1,
				})
				else nil,
		}),

		-- Keybind and countdown sit above every overlay, not inside Content with the icon. Both have
		-- to stay readable exactly when the slot is washed out -- that is when the player is waiting
		-- and looking at them -- and in the Studio original the keybind was half outside the slot and
		-- partly covered by the cooldown wash.
		KeyLabel = if props.keyLabel
			then e("TextLabel", {
				Text = props.keyLabel,
				Font = theme.font.action,
				TextColor3 = theme.color.iconReadyTint,
				TextScaled = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				BackgroundTransparency = 1,
				Position = UDim2.fromScale(0.07, 0.04),
				Size = UDim2.fromScale(0.4, 0.3),
				ZIndex = 10,
			})
			else nil,

		Timer = e("TextLabel", {
			Text = timerText,
			Visible = timerVisible,
			Font = theme.font.action,
			TextColor3 = theme.color.iconReadyTint,
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Center,
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(0.5, 0.58),
			Size = UDim2.fromScale(0.8, 0.42),
			ZIndex = 10,
		}),

		GCDOverlay = e("Frame", {
			Visible = gcdVisible,
			BackgroundColor3 = theme.color.gcdScrim,
			BackgroundTransparency = 0.7,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 7,
		}, {
			Corner = e("UICorner", { CornerRadius = UDim.new(0, theme.metrics.radiusControl) }),
			Gradient = e("UIGradient", {
				Color = ColorSequence.new(theme.color.gcdAccent),
				Rotation = -25,
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0),
					NumberSequenceKeypoint.new(0.5953, 0.1375),
					NumberSequenceKeypoint.new(1, 0.7312),
				}),
			}),
		}),

		StatusBlockOverlay = e("Frame", {
			Visible = blockedVisible,
			BackgroundColor3 = theme.color.castBlockedAccent,
			BackgroundTransparency = 0.4,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 9,
		}, {
			Corner = e("UICorner", { CornerRadius = UDim.new(0, theme.metrics.radiusControl) }),
			Gradient = e("UIGradient", {
				Color = ColorSequence.new(theme.color.iconReadyTint),
				Rotation = -64,
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0.0875),
					NumberSequenceKeypoint.new(0.5592, 0.075),
					NumberSequenceKeypoint.new(1, 0.75),
				}),
			}),
		}),
	})
end

return SkillSlotButton
