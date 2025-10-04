local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Timeline = require(script.Parent.Parent.Timeline)
local NetRay = require(ReplicatedStorage.Packages.NetRay)
local ExecutionService = require(script.Parent.Parent.ExecutionService)
-- Ensure event exists on server; GetEvent is client-only
local event = NetRay:RegisterEvent("SkillsEvent")

local BaseSkill = {}
BaseSkill.__index = BaseSkill

function BaseSkill.new(player: Player, data: any)
	local self = setmetatable({}, BaseSkill)
	self.player = player
	self.id = data.id or data.name
	self.name = data.name
	self.description = data.description
	self.level = data.level or 1
	self.cooldown = data.cooldown or 0
	self.gcd = data.gcd or 1.0
	-- Keep full server-side config for timing and other logic
	self.config = data
	return self
end

function BaseSkill:use()
	-- child should override
	error("BaseSkill:use() must be implemented by child: " .. tostring(self.name))
end

-- Emit a start phase; children can override before/after
function BaseSkill:emitStart(extra: any?)
	event:FireAllClients({ phase = "start", id = self.name, casterId = self.player.UserId, data = extra })
end

-- Emit an impact with optional cframe/targets and step index
-- Emit a generic FX signal (replaces old 'impact')
-- params:
--   step: number (combo step or sequence index)
--   opts: { cframe: CFrame?, anchor: { mode: string, name: string, offset: CFrame?, fallback: string? }?, fxKey: string?, lifetime: number?, meta: any? }
function BaseSkill:emitFX(step: number, opts: any?)
	local o = opts or {}
	event:FireAllClients({
		phase = "fx",
		id = self.name,
		casterId = self.player.UserId,
		step = step,
		cframe = o.cframe,
		anchor = o.anchor,
		fxKey = o.fxKey,
		lifetime = o.lifetime,
		data = o.meta,
	})
end

-- Emit a step begin (for playing combo step animations client-side)
function BaseSkill:emitStep(step: number, extra: any?)
	event:FireAllClients({
		phase = "step",
		id = self.name,
		casterId = self.player.UserId,
		step = step,
		data = extra,
	})
end

-- Emit an end/cleanup
function BaseSkill:emitEnd(extra: any?)
	event:FireAllClients({ phase = "end", id = self.name, casterId = self.player.UserId, data = extra })
end

-- Combo helpers: open/close combo wait window for client idle anims
function BaseSkill:emitComboWaitStart(durationSec: number, step: number, totalSteps: number)
	event:FireAllClients({
		phase = "combo_wait",
		open = true,
		id = self.name,
		casterId = self.player.UserId,
		step = step,
		total = totalSteps,
		duration = durationSec,
	})
end

function BaseSkill:emitComboWaitEnd()
	event:FireAllClients({ phase = "combo_wait", open = false, id = self.name, casterId = self.player.UserId })
end

-- optional: child override to schedule hits/FX
function BaseSkill:onCast(_ctx: any)
	-- no-op by default
end

function BaseSkill:schedule(steps: { { t: number, fn: () -> () } })
	local tl = Timeline.new()
	tl:sequence(steps)
	return tl
end

-- Execution helpers: wrap emitStart/emitEnd with execution lock semantics.
-- duration: optional planned execution length (auto-completes). If nil, skill must call completeExecution manually.
function BaseSkill:beginExecution(duration: number?, allowChain: boolean?)
	if self._execToken then return end -- already executing
	local token = ExecutionService.begin(self.player, self.name, {
		duration = duration,
		allowChainSkill = allowChain and self.name or nil,
	})
	if not token then
		return false
	end
	self._execToken = token
	self:emitStart()
	return true
end

function BaseSkill:completeExecution(reason: string?)
	if not self._execToken then return end
	local tok = self._execToken
	self._execToken = nil
	ExecutionService.complete(self.player, tok, reason)
	self:emitEnd({ reason = reason })
end

return BaseSkill
