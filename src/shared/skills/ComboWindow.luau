--!strict
-- ComboWindow: when a combo's next step may start, read the same way by both peers (the server
-- validates the press against it, the client predicts and buffers against it).
--
-- A step can be cancelled into the next once its hit has landed and part of its follow-through has
-- played, rather than only when its animation ends: waiting out the whole swing after the blow has
-- connected is what made fast pressing feel like waiting on the animation. The window still closes
-- when it did before, so opening it earlier only adds time to press in.

local ComboWindow = {}

-- Share of the follow-through (from the hit to the end of the step's animation) that plays before
-- the next step may cut it off. 0 cancels on the hit, 1 waits for the whole animation.
ComboWindow.DEFAULT_CANCEL_SHARE = 0.5

export type Window = {
	-- Seconds from the step's start until the next step may begin.
	openDelay: number,
	-- Seconds the window stays open from `openDelay`.
	length: number,
}

-- `stepDuration`, `hitDelay`, `stepDelay` and `window` are already scaled by tempo. `cancelShare`
-- is the combo's own (`combo.cancelShare`), else the default.
function ComboWindow.resolve(
	stepDuration: number,
	hitDelay: number,
	stepDelay: number,
	window: number,
	cancelShare: number?
): Window
	local share = math.clamp(cancelShare or ComboWindow.DEFAULT_CANCEL_SHARE, 0, 1)
	local closesAfter = stepDuration + stepDelay + window
	local openDelay = stepDuration + stepDelay
	if hitDelay < stepDuration then
		openDelay = hitDelay + (stepDuration - hitDelay) * share + stepDelay
	end
	return { openDelay = openDelay, length = math.max(closesAfter - openDelay, 0) }
end

return ComboWindow
