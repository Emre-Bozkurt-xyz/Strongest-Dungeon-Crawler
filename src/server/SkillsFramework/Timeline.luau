--!strict
-- Simple timeline scheduler utility for skills

local Timeline = {}
Timeline.__index = Timeline

export type Step = { t: number, fn: () -> () }

function Timeline.new()
	local self = setmetatable({ _tasks = {} :: { RBXScriptConnection? }, _cancelled = false }, Timeline)
	return self
end

function Timeline:after(t: number, fn: () -> ())
	task.delay(t, function()
		if self._cancelled then
			return
		end
		fn()
	end)
	return self
end

function Timeline:sequence(steps: { Step })
	table.sort(steps, function(a, b)
		return (a.t or 0) < (b.t or 0)
	end)
	for _, s in ipairs(steps) do
		self:after(s.t or 0, s.fn)
	end
	return self
end

function Timeline:cancel()
	self._cancelled = true
end

return Timeline
