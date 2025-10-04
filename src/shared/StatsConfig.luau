--!strict
-- Deprecated: StatsConfig moved to server (ServerScriptService.Server.StatsConfig)
-- This stub intentionally exposes nothing to the client.

local RunService = game:GetService("RunService")

if RunService:IsClient() then
	error("StatsConfig is server-only. Do not require it on the client. See ServerScriptService/Server/StatsConfig.")
end

return {}
