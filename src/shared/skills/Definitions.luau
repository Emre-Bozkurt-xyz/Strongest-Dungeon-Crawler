--!strict
-- Deprecated: behavior defs removed in favor of class-based skills.
-- For visuals, use skills/ClientSpec instead.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ClientSpec = require(ReplicatedStorage.Shared.skills.ClientSpec)

warn("[skills/Definitions] is deprecated. Use skills/ClientSpec for client visuals.")

return ClientSpec
