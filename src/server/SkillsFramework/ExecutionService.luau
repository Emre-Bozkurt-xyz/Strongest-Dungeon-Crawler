--!strict
-- ExecutionService: Manages per-entity skill execution (cast/active) phase.
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

type Caster = Instance

local active: { [Caster]: ExecState } = {}
local listeners: { (Caster, string, string) -> () } = {}

local function now(): number
	return os.clock()
end

local function fireComplete(caster: Caster, skill: string, reason: string)
	for _, cb in ipairs(listeners) do
		local ok = pcall(cb, caster, skill, reason)
		if not ok then
			warn("ExecutionService listener error")
		end
	end
end

function ExecutionService.onCompleted(cb: (Caster, string, string) -> ())
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

function ExecutionService.isLocked(caster: Caster): (boolean, string?)
	local st = active[caster]
	if st then
		return true, st.skill
	end
	return false, nil
end

local function autoFinish(caster: Caster, token: number)
	local st = active[caster]
	if not st or st.token ~= token then return end
	-- auto completion
	active[caster] = nil
	fireComplete(caster, st.skill, "auto")
end

function ExecutionService.begin(caster: Caster, skillName: string, opts: { duration: number?, allowChainSkill: string? }?): number?
	local st = active[caster]
	if st then
		-- Allow chaining if same skill and chaining requested
		if not (opts and opts.allowChainSkill and st.skill == opts.allowChainSkill) then
			return nil
		end
	end
	local token = math.random(1, 2^31 - 1)
	local duration = opts and opts.duration or nil
	active[caster] = {
		skill = skillName,
		token = token,
		startedAt = now(),
		finishAt = duration and (now() + duration) or nil,
		allowChainSkill = opts and opts.allowChainSkill or nil,
	}
	if duration and duration > 0 then
		task.delay(duration, function()
			autoFinish(caster, token)
		end)
	end
	return token
end

function ExecutionService.complete(caster: Caster, token: number, reason: string?)
	local st = active[caster]
	if not st or st.token ~= token then return end
	active[caster] = nil
	fireComplete(caster, st.skill, reason or "normal")
end

return ExecutionService
