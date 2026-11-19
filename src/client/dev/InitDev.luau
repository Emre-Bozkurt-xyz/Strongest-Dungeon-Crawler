--!strict
-- Client dev-only hooks: debug defaults, the dev command system (client commands and the DevClient
-- automation entry point) and the loaded scenario's client overrides.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DebugConfig = require(ReplicatedStorage.Shared.Debug.DebugConfig)

local Dev = {}

function Dev.start(_ctx)
	DebugConfig.setMany({
		sessionPerf = false,
		projectiles = false,
		inputFlow = true,
	})

	require(script.Parent.Commands).start()
	require(script.Parent.ScenarioOverrides).start()
end

return Dev
