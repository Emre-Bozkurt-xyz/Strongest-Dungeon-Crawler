--!strict
-- The System's switch-on: how a surface opens and closes, as pure frame math shared by the world
-- panels (PanelHost) and screen UI (components/SwitchOn).
--
-- Opening: a line of light draws out from the centre, splits in two, and the pair open outward
-- revealing the surface between them, then dim away. Closing runs it backward, faster: the band
-- collapses to the line and the line shrinks to nothing. Fixed times eased to a hard stop, because a
-- fade or a spring's settling tail is what reads as floaty.

local Ease = require(script.Parent.Ease)

local SwitchOn = {}

export type Frame = {
	-- Height of the revealed band, 0..1 of the surface.
	band: number,
	-- Length of the light lines, 0..1 of the surface's width.
	lineLength: number,
	lineTransparency: number,
	-- The surface as a whole.
	transparency: number,
}

SwitchOn.CLOSED = table.freeze({ band = 0, lineLength = 0, lineTransparency = 1, transparency = 1 }) :: Frame
SwitchOn.OPEN = table.freeze({ band = 1, lineLength = 1, lineTransparency = 1, transparency = 0 }) :: Frame

-- How long a transition from band height `from` takes. A reversal mid-way covers only the distance
-- left, at the same pace.
function SwitchOn.duration(opening: boolean, from: number, timing: { reveal: number, conceal: number }): number
	return if opening then timing.reveal * (1 - from) else timing.conceal * from
end

-- The frame at progress `t` (0..1) of a transition that started at band height `from`.
function SwitchOn.frame(opening: boolean, t: number, from: number): Frame
	if opening then
		-- First quarter: the line draws out. Then the band throws open and brakes onto full height,
		-- the surface coming up with it; the lines dim once it is nearly open. A reversal that starts
		-- with the band already part-open skips the line.
		local lineIn = if from > 0 then 1 else Ease.quartOut(Ease.clamp01(t / 0.25))
		local open = if from > 0 then t else Ease.clamp01((t - 0.25) / 0.75)
		return {
			band = from + (1 - from) * Ease.expoOut(open),
			lineLength = lineIn,
			lineTransparency = Ease.clamp01((t - 0.65) / 0.35),
			transparency = 1 - Ease.clamp01((t - 0.2) / 0.2),
		}
	end
	-- The band collapses slowly then snaps to the line, the surface cutting out with it, and the line
	-- shrinks to nothing in the last fifth.
	return {
		band = from * (1 - Ease.quartIn(Ease.clamp01(t / 0.8))),
		lineLength = 1 - Ease.quartIn(Ease.clamp01((t - 0.8) / 0.2)),
		lineTransparency = 0,
		transparency = Ease.clamp01((t - 0.6) / 0.2),
	}
end

return SwitchOn
