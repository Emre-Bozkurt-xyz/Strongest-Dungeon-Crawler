--!strict
-- ComboService: Tracks per-player per-skill combo state and windows + per-step lockouts

export type ComboState = {
	step: number,
	expiresAt: number,
	token: number,
	steps: number,
	window: number,
	nextAllowedTime: number?, -- earliest time next input can advance
	lastAdvanceTime: number?,
}

local ComboService = {}
local state: { [Player]: { [string]: ComboState } } = {}

local function now(): number
	return tick()
end

local function ensurePlayerMap(player: Player): { [string]: ComboState }
	local m = state[player]
	if not m then
		m = {}
		state[player] = m
	end
	return m
end

-- stepDelays: array where index = current step, value = min seconds before accepting NEXT advance
function ComboService.nextStep(
	player: Player,
	skillName: string,
	steps: number,
	window: number,
	stepDelays: { number }?
): (number, number, boolean)
	local m = ensurePlayerMap(player)
	local s = m[skillName]
	local t = now()
	if s and t <= s.expiresAt then
		-- Enforce per-step delay gate
		if s.nextAllowedTime and t < s.nextAllowedTime then
			-- Still locked; do not advance; return current step without changing token
			return s.step, s.token, false
		end
		if s.step < s.steps then
			s.step += 1
		else
			s.step = 1 -- restart chain if pressed after completion but still within window
		end
		s.expiresAt = t + window
		s.token += 1
		s.steps = steps
		s.window = window
		s.lastAdvanceTime = t
		if stepDelays then
			local delay = stepDelays[s.step] or 0
			if delay > 0 then
				s.nextAllowedTime = t + delay
			else
				s.nextAllowedTime = nil
			end
		end
		return s.step, s.token, true
	else
		local newS: ComboState = {
			step = 1,
			expiresAt = t + window,
			token = 1,
			steps = steps,
			window = window,
			lastAdvanceTime = t,
			nextAllowedTime = (stepDelays and stepDelays[1] and stepDelays[1] > 0) and (t + stepDelays[1]) or nil,
		}
		m[skillName] = newS
		return 1, newS.token, true
	end
end

function ComboService.isExpired(player: Player, skillName: string, token: number): boolean
	local m = state[player]
	local s = m and m[skillName]
	if not s then
		return true
	end
	if s.token ~= token then
		return false
	end -- superseded by newer press
	if now() > s.expiresAt then
		m[skillName] = nil
		return true
	end
	return false
end

function ComboService.clear(player: Player, skillName: string)
	local m = state[player]
	if m then
		m[skillName] = nil
		if next(m) == nil then
			state[player] = nil
		end
	end
end

return ComboService
