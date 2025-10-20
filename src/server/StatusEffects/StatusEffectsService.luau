--!strict
-- Server-side status effects manager: register, apply, tick, and remove timed effects with stacking rules

local RunService = game:GetService("RunService")

local StatusEffectsService = {}

export type EffectContext = {
	applyDamage: (target: Instance, amount: number, source: Instance?, opts: any?) -> any,
}

export type StackingMode = "aggregate" | "multi" | "charges"
export type TickMode = "perEffect" | "perStack"
export type DurationPolicy = "refresh" | "extend" | "independent"
export type CapPolicy = "refreshOldest" | "refreshWeakest" | "reject"

export type EffectDef = {
	id: string,
	duration: number?, -- base duration in seconds if not provided via params
	maxStacks: number?, -- default 1
	tickInterval: number?, -- seconds between ticks; nil/<=0 means every Heartbeat
	-- Stacking/ticking policies (optional; defaults preserve old behavior)
	stacking: StackingMode?, -- default "aggregate"
	tickMode: TickMode?, -- default: aggregate/charges->perEffect, multi->perStack
	durationPolicy: DurationPolicy?, -- aggregate/charges: "refresh" (default) | "extend"; multi is always independent per-entry
	capPolicy: CapPolicy?, -- when at max stacks: default "refreshOldest"
	-- Optional helpers for advanced policies
	paramCombine: ((entries: { any }) -> any)?, -- combine params for aggregate ticks
	getPotency: ((params: any) -> number)?, -- for refreshWeakest
	-- Callbacks
	onApply: ((target: Instance, source: Instance?, params: any?, stacks: number) -> ())?,
	onRefresh: ((target: Instance, source: Instance?, params: any?, stacks: number) -> ())?,
	onTick: ((target: Instance, source: Instance?, params: any?, stacks: number, dt: number, ctx: EffectContext) -> ())?,
	onRemove: ((target: Instance, source: Instance?, stacks: number) -> ())?,
}

export type ActiveEntry = {
	params: any?,
	source: Instance?,
	expiresAt: number,
	nextTickAt: number?,
	lastTick: number,
	potency: number?,
	addedAt: number,
}

export type ActiveEffectState = {
	id: string,
	mode: StackingMode,
	stacks: number,
	expiresAt: number, -- os.clock() time (aggregate/charges-global)
	params: any?, -- aggregate combined/last params
	source: Instance?,
	def: EffectDef,
	lastTick: number,
	nextTickAt: number?, -- aggregate/charges per-effect tick time
	-- Multi / Aggregate contributors
	entries: { ActiveEntry }?,
	-- Charges with independent timers
	chargeExpiries: { number }?,
}

-- Load central registry
local registry: { [string]: EffectDef } = require(script.Parent.EffectsIndex)
-- Active table keyed by root model (or instance) to map of effectId -> state
local active: { [Instance]: { [string]: ActiveEffectState } } = {}

-- Optional context set by the consumer (e.g., CombatService) to avoid cyclic requires
local context: EffectContext? = nil
function StatusEffectsService.setContext(ctx: EffectContext)
	context = ctx
end

local function rootOf(inst: Instance): Instance
	if inst:IsA("Model") then
		return inst
	end
	local cur: Instance? = inst
	while cur and not cur:IsA("Model") do
		cur = cur.Parent
	end
	return cur or inst
end

local function getStacksFor(state: ActiveEffectState): number
	if state.mode == "multi" then
		local entries = state.entries :: { ActiveEntry }?
		return entries and #entries or 0
	elseif state.mode == "charges" then
		local arr = state.chargeExpiries :: { number }?
		return arr and #arr or 0
	end
	return state.stacks
end

function StatusEffectsService.has(target: Instance, id: string): boolean
	local root = rootOf(target)
	local bucket = active[root]
	return bucket ~= nil and bucket[id] ~= nil and getStacksFor(bucket[id]) > 0
end

function StatusEffectsService.getStacks(target: Instance, id: string): number
	local root = rootOf(target)
	local bucket = active[root]
	local st = bucket and bucket[id]
	if not st then
		return 0
	end
	return getStacksFor(st)
end

function StatusEffectsService.remove(target: Instance, id: string)
	local root = rootOf(target)
	local bucket = active[root]
	if not bucket then
		return
	end
	local st = bucket[id]
	if not st then
		return
	end
	if st.def.onRemove then
		pcall(st.def.onRemove, root, st.source, getStacksFor(st))
	end
	bucket[id] = nil
	if next(bucket) == nil then
		active[root] = nil
	end
end

function StatusEffectsService.clearAll(target: Instance)
	local root = rootOf(target)
	local bucket = active[root]
	if not bucket then
		return
	end
	for id, st in bucket do
		if st.def.onRemove then
			pcall(st.def.onRemove, root, st.source, getStacksFor(st))
		end
		bucket[id] = nil
	end
	active[root] = nil
end

local function ensureState(
	id: string,
	def: EffectDef,
	source: Instance?,
	params: any,
	now: number,
	duration: number
): ActiveEffectState
	local mode: StackingMode = def.stacking or "aggregate"
	local state: ActiveEffectState = {
		id = id,
		mode = mode,
		stacks = 0,
		expiresAt = now + duration,
		params = params,
		source = source,
		def = def,
		lastTick = now,
		nextTickAt = (def.tickInterval and def.tickInterval > 0) and (now + def.tickInterval) or nil,
		entries = (mode == "multi" or def.paramCombine) and ({} :: { ActiveEntry }) or nil,
		chargeExpiries = (mode == "charges" and (def.durationPolicy == "independent")) and ({} :: { number }) or nil,
	}
	return state
end

local function addOrReplaceEntry(
	st: ActiveEffectState,
	def: EffectDef,
	params: any,
	source: Instance?,
	now: number,
	duration: number
)
	local entriesOpt = st.entries :: { ActiveEntry }?
	if not entriesOpt then
		st.entries = {} :: { ActiveEntry }
		entriesOpt = st.entries
	end
	local entriesNN = entriesOpt :: { ActiveEntry }
	local maxStacks = def.maxStacks or 1
	local newEntry: ActiveEntry = {
		params = params,
		source = source,
		expiresAt = now + duration,
		nextTickAt = (def.tickInterval and def.tickInterval > 0) and (now + def.tickInterval) or nil,
		lastTick = now,
		potency = def.getPotency and def.getPotency(params) or nil,
		addedAt = now,
	}
	if #entriesNN < maxStacks then
		table.insert(entriesNN, newEntry)
		return "applied"
	end
	local capPolicy: CapPolicy = def.capPolicy or "refreshOldest"
	if capPolicy == "reject" then
		return "rejected"
	elseif capPolicy == "refreshWeakest" and def.getPotency then
		-- ensure non-empty
		if #entriesNN == 0 then
			table.insert(entriesNN, newEntry)
			return "applied"
		end
		local weakestIndex = 1
		local weakestVal = entriesNN[1].potency or math.huge
		for i = 2, #entriesNN do
			local p = entriesNN[i].potency or math.huge
			if p < weakestVal then
				weakestVal = p
				weakestIndex = i
			end
		end
		entriesNN[weakestIndex] = newEntry
		return "refreshed"
	else
		-- refreshOldest
		-- ensure non-empty
		if #entriesNN == 0 then
			table.insert(entriesNN, newEntry)
			return "applied"
		end
		local oldestIndex = 1
		local oldestTime = entriesNN[1].expiresAt
		for i = 2, #entriesNN do
			if entriesNN[i].expiresAt < oldestTime then
				oldestTime = entriesNN[i].expiresAt
				oldestIndex = i
			end
		end
		entriesNN[oldestIndex] = newEntry
		return "refreshed"
	end
end

local function recomputeAggregateParams(st: ActiveEffectState)
	local def = st.def
	if def.paramCombine then
		local entriesOpt = st.entries :: { ActiveEntry }?
		if not entriesOpt or #entriesOpt == 0 then
			return
		end
		local entriesNN = entriesOpt :: { ActiveEntry }
		local list: { any } = {}
		for _, e in entriesNN do
			table.insert(list, e.params)
		end
		st.params = def.paramCombine(list)
	end
end

function StatusEffectsService.apply(target: Instance, id: string, source: Instance?, params: any?): boolean
	local def = registry[id]
	if not def then
		warn("StatusEffectsService: effect not registered:", id)
		return false
	end
	local root = rootOf(target)
	local now = os.clock()
	local bucket = active[root]
	if not bucket then
		bucket = {}
		active[root] = bucket
	end
	local st = bucket[id]
	local maxStacks = def.maxStacks or 1
	local duration = (params and (params :: any).duration) or def.duration or 0
	local mode: StackingMode = def.stacking or "aggregate"
	local durationPolicy: DurationPolicy = def.durationPolicy or "refresh"

	if duration <= 0 then
		-- instant effect: just call onApply once and don't store
		if def.onApply then
			pcall(def.onApply, root, source, params, 1)
		end
		return true
	end

	if not st then
		st = ensureState(id, def, source, params, now, duration)
		bucket[id] = st
	end

	-- Apply per mode
	if mode == "multi" then
		-- independent entries per stack
		local status = addOrReplaceEntry(st, def, params, source, now, duration)
		local entriesOpt = st.entries :: { ActiveEntry }?
		if not entriesOpt then
			st.entries = {} :: { ActiveEntry }
			entriesOpt = st.entries
		end
		local entriesNN = entriesOpt :: { ActiveEntry }
		st.stacks = #entriesNN
		-- overall expiry: max of entries
		local maxExp = now
		for _, e in entriesNN do
			if e.expiresAt > maxExp then
				maxExp = e.expiresAt
			end
		end
		st.expiresAt = maxExp
		if def.onApply and status == "applied" then
			pcall(def.onApply, root, source, params, st.stacks)
		elseif def.onRefresh and status == "refreshed" then
			pcall(def.onRefresh, root, source, params, st.stacks)
		end
		return true
	elseif mode == "charges" then
		-- stacks as charges; durations may be independent
		if def.durationPolicy == "independent" then
			local arrOpt = st.chargeExpiries :: { number }?
			if not arrOpt then
				st.chargeExpiries = {} :: { number }
				arrOpt = st.chargeExpiries
			end
			local arrNN = arrOpt :: { number }
			if #arrNN < maxStacks then
				table.insert(arrNN, now + duration)
				st.stacks = #arrNN
				if def.onApply then
					pcall(def.onApply, root, source, params, st.stacks)
				end
			else
				-- at cap: honor capPolicy
				local cap: CapPolicy = def.capPolicy or "refreshOldest"
				if cap ~= "reject" then
					-- refresh oldest expiry
					-- ensure non-empty
					local oldestIndex = 1
					local oldestTime = arrNN[1]
					for i = 2, #arrNN do
						if arrNN[i] < oldestTime then
							oldestTime = arrNN[i]
							oldestIndex = i
						end
					end
					arrNN[oldestIndex] = now + duration
					if def.onRefresh then
						pcall(def.onRefresh, root, source, params, #arrNN)
					end
				end
			end
			-- keep global expiresAt as max for convenience
			local maxExp2 = now
			for _, t in arrNN do
				if t > maxExp2 then
					maxExp2 = t
				end
			end
			st.expiresAt = maxExp2
			return true
		else
			-- global expiry; increase stacks up to cap
			if st.stacks < maxStacks then
				st.stacks += 1
				if def.onApply then
					pcall(def.onApply, root, source, params, st.stacks)
				end
			else
				if def.onRefresh then
					pcall(def.onRefresh, root, source, params, st.stacks)
				end
			end
			-- duration policy
			if durationPolicy == "extend" then
				st.expiresAt = (st.expiresAt or now) + duration
			else
				st.expiresAt = now + duration
			end
			return true
		end
	else
		-- aggregate (default)
		-- stacks bump up to max
		if st.stacks < maxStacks then
			st.stacks += 1
			if def.onApply then
				pcall(def.onApply, root, source, params, st.stacks)
			end
		else
			if def.onRefresh then
				pcall(def.onRefresh, root, source, params, st.stacks)
			end
		end
		-- params management
		if def.paramCombine then
			local entries2Opt = st.entries :: { ActiveEntry }?
			if not entries2Opt then
				st.entries = {} :: { ActiveEntry }
				entries2Opt = st.entries
			end
			local entries2NN = entries2Opt :: { ActiveEntry }
			if #entries2NN < maxStacks then
				table.insert(entries2NN, {
					params = params,
					source = source,
					expiresAt = now + duration,
					nextTickAt = (def.tickInterval and def.tickInterval > 0) and (now + def.tickInterval) or nil,
					lastTick = now,
					addedAt = now,
				})
			else
				local cap2: CapPolicy = def.capPolicy or "refreshOldest"
				if cap2 ~= "reject" then
					if cap2 == "refreshWeakest" and def.getPotency then
						if #entries2NN == 0 then
							table.insert(entries2NN, {
								params = params,
								source = source,
								expiresAt = now + duration,
								nextTickAt = (def.tickInterval and def.tickInterval > 0) and (now + def.tickInterval)
									or nil,
								lastTick = now,
								addedAt = now,
							})
						else
							local weakestIndex2 = 1
							local weakestVal2 = def.getPotency(entries2NN[1].params)
							for i = 2, #entries2NN do
								local pv = def.getPotency(entries2NN[i].params)
								if pv < weakestVal2 then
									weakestVal2 = pv
									weakestIndex2 = i
								end
							end
							entries2NN[weakestIndex2] = {
								params = params,
								source = source,
								expiresAt = now + duration,
								nextTickAt = (def.tickInterval and def.tickInterval > 0) and (now + def.tickInterval)
									or nil,
								lastTick = now,
								addedAt = now,
							}
						end
					else
						-- refreshOldest by addedAt
						if #entries2NN == 0 then
							table.insert(entries2NN, {
								params = params,
								source = source,
								expiresAt = now + duration,
								nextTickAt = (def.tickInterval and def.tickInterval > 0) and (now + def.tickInterval)
									or nil,
								lastTick = now,
								addedAt = now,
							})
						else
							local oldestIndex2 = 1
							local oldest2 = entries2NN[1].addedAt
							for i = 2, #entries2NN do
								if entries2NN[i].addedAt < oldest2 then
									oldest2 = entries2NN[i].addedAt
									oldestIndex2 = i
								end
							end
							entries2NN[oldestIndex2] = {
								params = params,
								source = source,
								expiresAt = now + duration,
								nextTickAt = (def.tickInterval and def.tickInterval > 0) and (now + def.tickInterval)
									or nil,
								lastTick = now,
								addedAt = now,
							}
						end
					end
				end
			end
			recomputeAggregateParams(st)
		else
			-- fallback: last param wins
			st.params = params or st.params
		end
		-- duration policy
		if durationPolicy == "extend" then
			st.expiresAt = (st.expiresAt or now) + duration
		else
			st.expiresAt = now + duration
		end
		return true
	end
end

-- Heartbeat processing for ticking and expiration
RunService.Heartbeat:Connect(function(dt: number)
	local now = os.clock()
	for root, bucket in active do
		for id, st in bucket do
			local def = st.def
			if st.mode == "multi" then
				-- remove expired entries
				local entriesOpt = st.entries :: { ActiveEntry }?
				if not entriesOpt then
					st.entries = {} :: { ActiveEntry }
					entriesOpt = st.entries
				end
				local entriesNN = entriesOpt :: { ActiveEntry }
				local i = 1
				local maxExp = now
				while i <= #entriesNN do
					if now >= entriesNN[i].expiresAt then
						table.remove(entriesNN, i)
					else
						if entriesNN[i].expiresAt > maxExp then
							maxExp = entriesNN[i].expiresAt
						end
						i += 1
					end
				end
				st.stacks = #entriesNN
				st.expiresAt = maxExp
				if st.stacks <= 0 then
					if def.onRemove then
						pcall(def.onRemove, root, st.source, 0)
					end
					bucket[id] = nil
					continue
				end
				-- tick per entry if requested
				if def.onTick then
					for _, e in entriesNN do
						local doTick = false
						local interval = def.tickInterval or 0
						if interval <= 0 then
							doTick = true
						elseif not e.nextTickAt or now >= e.nextTickAt then
							doTick = true
							e.nextTickAt = now + interval
						end
						if doTick then
							pcall(def.onTick, root, e.source or st.source, e.params, st.stacks, dt, context :: any)
							e.lastTick = now
						end
					end
				end
			elseif st.mode == "charges" then
				local arrOpt = st.chargeExpiries :: { number }?
				if not arrOpt then
					st.chargeExpiries = {} :: { number }
					arrOpt = st.chargeExpiries
				end
				local arrNN = arrOpt :: { number }
				-- independent charge expiry
				local i2 = 1
				local maxExp3 = now
				while i2 <= #arrNN do
					if now >= arrNN[i2] then
						table.remove(arrNN, i2)
					else
						if arrNN[i2] > maxExp3 then
							maxExp3 = arrNN[i2]
						end
						i2 += 1
					end
				end
				st.stacks = #arrNN
				st.expiresAt = maxExp3
				if st.stacks <= 0 then
					if def.onRemove then
						pcall(def.onRemove, root, st.source, 0)
					end
					bucket[id] = nil
					continue
				end
				-- optional per-effect ticking for charges (global)
				if def.onTick then
					local doTick2 = false
					local interval2 = def.tickInterval or 0
					if interval2 <= 0 then
						doTick2 = true
					elseif not st.nextTickAt or now >= st.nextTickAt then
						doTick2 = true
						st.nextTickAt = now + interval2
					end
					if doTick2 then
						pcall(def.onTick, root, st.source, st.params, st.stacks, dt, context :: any)
						st.lastTick = now
					end
				end
			else
				-- aggregate
				if now >= st.expiresAt then
					if def.onRemove then
						pcall(def.onRemove, root, st.source, st.stacks)
					end
					bucket[id] = nil
					continue
				end
				if def.onTick then
					local doTick3 = false
					local interval3 = def.tickInterval or 0
					if interval3 <= 0 then
						doTick3 = true
					elseif not st.nextTickAt or now >= st.nextTickAt then
						doTick3 = true
						st.nextTickAt = now + interval3
					end
					if doTick3 then
						-- params may be combined
						if def.paramCombine then
							recomputeAggregateParams(st)
						end
						pcall(def.onTick, root, st.source, st.params, st.stacks, dt, context :: any)
						st.lastTick = now
					end
				end
			end
		end
		if next(bucket) == nil then
			active[root] = nil
		end
	end
end)

return StatusEffectsService
