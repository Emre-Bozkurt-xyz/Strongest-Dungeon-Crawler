--!strict
-- ExecutionService: Manages per-entity skill execution (cast/active) phase.
-- Phases separation: execution (no other skills except allowed chain) -> cooldown + optional GCD.
-- API:
--   ExecutionService.begin(player, skillName, opts) -> token?, state? (nil if busy & cannot chain)
--     opts = { duration: number? (auto-complete), allowChainSkill: string?, tempo: number?, durationScale: number?, timing: { [string]: any }?, metadata: { [string]: any }? }
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
	plannedDuration: number?,
	targetDuration: number?,
	tempo: number?,
	durationScale: number?,
	timing: { [string]: any }?,
	jumpLocked: boolean?,
	metadata: { [string]: any }?,
	completedAt: number?,
	reason: string?,
}

type Caster = Instance

local active: { [Caster]: ExecState } = {}
local listeners: { (Caster, string, string, ExecState?) -> () } = {}

local function now(): number
	return os.clock()
end

local function shallowCopy(source: { [string]: any }?): { [string]: any }?
	if source == nil then
		return nil
	end
	return table.clone(source)
end

local function fireComplete(caster: Caster, skill: string, reason: string, state: ExecState?)
	for _, cb in ipairs(listeners) do
		local ok = pcall(cb, caster, skill, reason, state)
		if not ok then
			warn("ExecutionService listener error")
		end
	end
end

function ExecutionService.onCompleted(cb: (Caster, string, string, ExecState?) -> ())
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
	st.completedAt = now()
	st.reason = "auto"

	if st.jumpLocked then
		print("Unlocking Jump")
		local humanoid = nil
		if caster:IsA("Player") then
			local char = caster.Character
			if char then
				humanoid = char:FindFirstChildWhichIsA("Humanoid")
			end
		else
			humanoid = caster:FindFirstChildWhichIsA("Humanoid", true)
		end

		if humanoid then
			humanoid.JumpPower = (st.metadata :: any).previousJumpPower or 50 -- Default jump power
			humanoid.AutoJumpEnabled = (st.metadata :: any).previousAutoJumpEnabled or true
		end
	end

	active[caster] = nil
	fireComplete(caster, st.skill, "auto", st)
end

type BeginOptions = {
	duration: number?,
	allowChainSkill: string?,
	tempo: number?,
	durationScale: number?,
	timing: { [string]: any }?,
	metadata: { [string]: any }?,
	targetDuration: number?,
	lockJump: boolean?,
}

local function cloneTiming(timing: { [string]: any }?): { [string]: any }?
	if timing == nil then
		return nil
	end
	local cloned = table.clone(timing)
	local meta = timing.metadata
	if meta ~= nil and type(meta) == "table" then
		cloned.metadata = shallowCopy(meta)
	end
	return cloned
end

function ExecutionService.begin(caster: Caster, skillName: string, opts: BeginOptions?): (number?, ExecState?)
	local st = active[caster]
	if st then
		-- Allow chaining if same skill and chaining requested
		if not (opts and opts.allowChainSkill and st.skill == opts.allowChainSkill) then
			return nil, nil
		end
	end
	local token = math.random(1, 2^31 - 1)
	local duration = opts and opts.duration or nil
	local targetDuration = opts and opts.targetDuration or duration
	local startedAt = now()
	local plannedFinish = duration and (startedAt + duration) or nil
	local tempo = opts and opts.tempo or nil
	local durationScale = opts and opts.durationScale or nil
	local timing = cloneTiming(opts and opts.timing or nil)

	if opts and opts.lockJump then
		local humanoid = caster:FindFirstChildWhichIsA("Humanoid", true)
		if caster:IsA("Player") then
			local char = caster.Character
			if char then
				humanoid = char:FindFirstChildWhichIsA("Humanoid")
			end
		end

		-- Ensure metadata table exists, avoid linting error
		opts.metadata = opts.metadata or {}

		if humanoid and opts.metadata then
			opts.metadata.previousJumpPower = humanoid.JumpPower
			opts.metadata.previousAutoJumpEnabled = humanoid.AutoJumpEnabled
			humanoid.JumpPower = 0
			humanoid.AutoJumpEnabled = false
		end
	end

	active[caster] = {
		skill = skillName,
		token = token,
		startedAt = startedAt,
		finishAt = plannedFinish,
		allowChainSkill = opts and opts.allowChainSkill or nil,
		plannedDuration = duration,
		targetDuration = targetDuration,
		tempo = tempo,
		durationScale = durationScale or (timing and timing.durationScale) or nil,
		timing = timing,
		jumpLocked = opts and opts.lockJump or nil,
		metadata = shallowCopy(opts and opts.metadata or nil),
	}
	if duration and duration > 0 then
		task.delay(duration, function()
			autoFinish(caster, token)
		end)
	end

	

	return token, active[caster]
end

function ExecutionService.complete(caster: Caster, token: number, reason: string?)
	local st = active[caster]
	if not st or st.token ~= token then return end
	st.completedAt = now()
	st.reason = reason or "normal"

	if st.jumpLocked then
		local humanoid = nil
		if caster:IsA("Player") then
			local char = caster.Character
			if char then
				humanoid = char:FindFirstChildWhichIsA("Humanoid")
			end
		else
			humanoid = caster:FindFirstChildWhichIsA("Humanoid", true)
		end

		if humanoid then
			humanoid.JumpPower = (st.metadata :: any).previousJumpPower or 50 -- Default jump power
			humanoid.AutoJumpEnabled = (st.metadata :: any).previousAutoJumpEnabled or true
		end
	end

	active[caster] = nil
	fireComplete(caster, st.skill, reason or "normal", st)
end

function ExecutionService.annotate(caster: Caster, token: number, update: { [string]: any }?)
	if not update then
		return false
	end
	local st = active[caster]
	if not st or st.token ~= token then
		return false
	end
	for key, value in pairs(update) do
		if value == nil then
			st[key] = nil
		elseif type(value) == "table" then
			if key == "timing" then
				st.timing = cloneTiming(value)
			else
				st[key] = table.clone(value)
			end
		else
			st[key] = value
		end
	end
	return true
end

function ExecutionService.getState(caster: Caster): ExecState?
	return active[caster]
end

return ExecutionService
