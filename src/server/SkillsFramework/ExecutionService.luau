--!strict
-- ExecutionService: Manages per-player skill execution (cast/active) phase.
-- Phases separation: execution (no other skills except allowed chain) -> cooldown + optional GCD.
-- API:
--   ExecutionService.begin(player, skillName, opts) -> token? (nil if busy & cannot chain)
--     opts = { duration: number? (auto-complete), allowChainSkill: string?, onComplete: (player, skillName, reason) -> () }?
--   ExecutionService.complete(player, token, reason?)
--   ExecutionService.isLocked(player) -> (bool, string?)
--   ExecutionService.onCompleted(cb) -> disconnect
-- Notes:
--   - If duration provided, schedules auto completion. Manual early completion cancels schedule.
--   - Chaining allowed when active.skill == allowChainSkill.

local ExecutionService = {}

export type ExecState = {
	skill: string,
	token: number,
	startedAt: number,
	finishAt: number?,
	allowChainSkill: string?,
	cancelled: boolean?,
}

local active: { [Player]: ExecState } = {}
local listeners: { (Player, string, string) -> () } = {}

local function now(): number
	return os.clock()
end

local function fireComplete(player: Player, skill: string, reason: string)
	for _, cb in ipairs(listeners) do
		local ok = pcall(cb, player, skill, reason)
		if not ok then
			warn("ExecutionService listener error")
		end
	end
end

function ExecutionService.onCompleted(cb: (Player, string, string) -> ())
	table.insert(listeners, cb)
	return function()
		for i, f in ipairs(listeners) do
			if f == cb then
				table.remove(listeners, i)
				break
			end
		end
	end
end

function ExecutionService.isLocked(player: Player): (boolean, string?)
	local st = active[player]
	if st then
		return true, st.skill
	end
	return false, nil
end

local function autoFinish(player: Player, token: number)
	local st = active[player]
	if not st or st.token ~= token then return end
	-- auto completion
	active[player] = nil
	fireComplete(player, st.skill, "auto")
end

function ExecutionService.begin(player: Player, skillName: string, opts: { duration: number?, allowChainSkill: string? }?): number?
	local st = active[player]
	if st then
		-- Allow chaining if same skill and chaining requested
		if not (opts and opts.allowChainSkill and st.skill == opts.allowChainSkill) then
			return nil
		end
	end
	local token = math.random(1, 2^31 - 1)
	local duration = opts and opts.duration or nil
	active[player] = {
		skill = skillName,
		token = token,
		startedAt = now(),
		finishAt = duration and (now() + duration) or nil,
		allowChainSkill = opts and opts.allowChainSkill or nil,
	}
	if duration and duration > 0 then
		task.delay(duration, function()
			autoFinish(player, token)
		end)
	end
	return token
end

function ExecutionService.complete(player: Player, token: number, reason: string?)
	local st = active[player]
	if not st or st.token ~= token then return end
	active[player] = nil
	fireComplete(player, st.skill, reason or "normal")
end

return ExecutionService
