--!strict
-- DebugConfig: centralized debug toggles (Studio-only).

local RunService = game:GetService("RunService")

local DebugConfig = {}

local IS_DEV = RunService:IsStudio()
local flags: { [string]: boolean } = {
	schema = false,
	sessionPerf = false,
	session = false,
	sessionHeartbeat = false,
	skills = false,
	skillsPhase3 = false,
	statusEffects = false,
	permissions = false,
	bootstrap = true,
	cancelDebug = false,
	combat = false,
	stagger = false,
	projectiles = false,
	inputFlow = false,
}

function DebugConfig.isDev(): boolean
	return IS_DEV
end

function DebugConfig.isEnabled(key: string): boolean
	if not IS_DEV then
		return false
	end
	return flags[key] == true
end

function DebugConfig.set(key: string, value: boolean)
	flags[key] = value
end

function DebugConfig.setMany(values: { [string]: boolean })
	for key, value in pairs(values) do
		flags[key] = value
	end
end

function DebugConfig.getAll(): { [string]: boolean }
	return table.clone(flags)
end

return DebugConfig
