--!strict
-- One skill slot: icon, the shrinking cooldown ring, the faint global-cooldown wash, the blocked-cast
-- tint, its keybind, and the countdown number. Ported from SkillSlotContainer in
-- docs/ui/SkillSlotContainer.rbxmx, framed like the item slots: a dark well, a hairline and corner
-- ticks.
--
-- Two states are added on top. Active (a combo or channel running) brightens the ticks, lights the
-- slot from its floor and lifts it -- all additive, because the cooldown states work by dimming and
-- anything that dims would read as "unavailable". Ready plays a single pulse the moment a cooldown
-- ends, a flash and a kick that reads in peripheral vision mid-fight.
--
-- Owns its own useSkillCooldown/useSkillRemaining calls so the number of hooks per render never
-- depends on how many slots the bar has -- each slot gets its own component precisely so its hooks
-- belong to it. The same goes for any hook that could otherwise become conditional on how much data
-- is currently available.
--
-- GCD and cast-blocked are shared across every slot -- SkillSlots.activate gates on the same GCD key
-- and the same status effect no matter which slot fired it -- so those arrive as bindings computed
-- once by the container (useGlobalCooldown, useCastBlocked) and passed down as props, rather than one
-- redundant Heartbeat connection per slot for an identical shared value.
--
-- Two deliberate simplifications: the GCD wash shows whenever the GCD is running, even on a slot
-- whose own cooldown already outlasts it; and sub-0.33s combo-step cooldowns are not filtered out,
-- because useSkillCooldown exposes only a 0..1 ratio, not the raw duration such a filter needs.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local Brackets = require(script.Parent.Parent.Parent.components.Brackets)
local ThemeContext = require(script.Parent.Parent.Parent.hooks.ThemeContext)
local useReadyPulse = require(script.Parent.Parent.Parent.hooks.useReadyPulse)
local useSpring = require(script.Parent.Parent.Parent.hooks.useSpring)
local useSkillCooldown = require(script.Parent.Parent.Parent.hooks.useSkillCooldown)
local useSkillRemaining = require(script.Parent.Parent.Parent.hooks.useSkillRemaining)
local SkillActions = require(script.Parent.Parent.Parent.actions.SkillActions)
local Selector = require(script.Parent.Parent.Parent.selectors.skillSlots)
local CooldownRadial = require(script.Parent.CooldownRadial)

local e = React.createElement

local BASE_TRANSPARENCY = 0.35

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

	-- Every "you cannot use this" visual is suppressed while the skill is running. A combo commits its
	-- cooldown on the first step, so without this the slot shows a countdown while the player is still
	-- swinging -- which is what the cooldown genuinely says, and exactly the wrong thing to show.
	local active = props.active == true
	local lift = useSpring(if active then 1 else 0, theme.motion.snap)
	local pulse = useReadyPulse(cooldownProgress)

	local joined = React.joinBindings({
		cooldown = cooldownProgress,
		gcd = props.gcdProgress,
	})

	local iconColor = joined:map(function(v)
		local locked = not active and (v.cooldown > 0 or v.gcd > 0)
		return if locked then theme.color.iconCooldownTint else theme.color.iconReadyTint
	end)

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
		BackgroundColor3 = theme.color.skillSlotSurface,
		BackgroundTransparency = BASE_TRANSPARENCY,
		BorderSizePixel = 0,
		[React.Event.Activated] = function()
			SkillActions.activate(props.index)
		end,
	}, {
		Hairline = e("UIStroke", {
			Color = if active then theme.color.skillSlotActiveStroke else theme.color.skillSlotStroke,
			Thickness = 1,
			Transparency = if active then 0 else 0.2,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		Ticks = e(Brackets, {
			size = "small",
			color = if active then theme.color.skillSlotActiveStroke else theme.color.stroke,
			edgeTransparency = 1,
			zIndex = 12,
		}),
		-- Lifts while active, and kicks once when the cooldown ends.
		Scale = e("UIScale", {
			Scale = React.joinBindings({ lift = lift, pulse = pulse }):map(function(v)
				return 1 + 0.08 * v.lift + 0.07 * v.pulse
			end),
		}),
		-- Light rising from the slot's floor while the skill runs, like a rarity-lit item slot.
		ActiveFloor = if active
			then e("Frame", {
				Size = UDim2.fromScale(1, 0.55),
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.fromScale(0, 1),
				BackgroundColor3 = theme.color.skillSlotActiveStroke,
				BorderSizePixel = 0,
				ZIndex = 4,
			}, {
				Fade = e("UIGradient", {
					Rotation = -90,
					Transparency = NumberSequence.new({
						NumberSequenceKeypoint.new(0, 0.45),
						NumberSequenceKeypoint.new(1, 1),
					}),
				}),
			})
			else nil,
		-- The ready flash: the whole slot lit, falling off over the pulse.
		ReadyFlash = e("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = theme.color.strokeStrong,
			BackgroundTransparency = pulse:map(function(v: number)
				return 1 - 0.55 * v
			end),
			BorderSizePixel = 0,
			ZIndex = 11,
		}),

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
				FontFace = theme.face.display,
				TextSize = theme.type.label,
				TextColor3 = theme.color.textPrimary,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(6, 4),
				Size = UDim2.fromOffset(30, 14),
				ZIndex = 10,
			}, {
				-- Readable over a bright icon without a backing box.
				Shadow = e("UIStroke", {
					Color = theme.color.skillSlotSurface,
					Thickness = 1,
					Transparency = 0.2,
				}),
			})
			else nil,

		Timer = e("TextLabel", {
			Text = timerText,
			Visible = timerVisible,
			FontFace = theme.face.mono,
			TextColor3 = theme.color.textHeading,
			TextSize = theme.type.title,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Center,
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(0.5, 0.58),
			Size = UDim2.fromScale(0.8, 0.42),
			ZIndex = 10,
		}, {
			-- The countdown sits over the icon, which is light; the outline keeps it readable.
			Outline = e("UIStroke", {
				Color = theme.color.skillSlotSurface,
				Thickness = 2,
				Transparency = 0.1,
			}),
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
