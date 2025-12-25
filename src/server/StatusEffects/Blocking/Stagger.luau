--!strict
-- Stagger effect - Brief interruption that blocks all actions and cancels active skills

local ServerScriptService = game:GetService("ServerScriptService")
local Server = ServerScriptService.Server

local SessionManager = require(Server.SkillsFramework.SessionManager)
local Registrar = require(Server.Services.Registrar)

return {
	id = "stagger",
	duration = 1.5, -- 1.5 second default stagger
	maxStacks = 1,
	stacking = "aggregate",
	durationPolicy = "refresh", -- New staggers reset duration
	blocksActions = {
		cast = true,
		move = true,
		jump = true,
		dodge = true,
		interact = true,
	},
	onApply = function(target: string, _source: string?, _params: any?, _stacks: number)
		-- Interrupt any active skill execution (handles both players and NPCs)
		local activeSession = SessionManager.getActive(target)
		if activeSession then
			SessionManager.cancel(activeSession.id, "staggered")
		end

		-- For NPCs, also stop animations - done via the Humanoid directly to avoid cyclic deps
		if not Registrar.isPlayerEntity(target) then
			local entity = Registrar.getEntityById(target)
			if entity and entity:IsA("Model") then
				local humanoid = entity:FindFirstChildWhichIsA("Humanoid") :: Humanoid?
				if humanoid then
					local animator = humanoid:FindFirstChildWhichIsA("Animator") :: Animator?
					if animator then
						for _, track in animator:GetPlayingAnimationTracks() do
							track:Stop(0.1)
						end
					end
				end
				-- Reset combat state attribute
				if entity:GetAttribute("CombatState") == "attacking" then
					entity:SetAttribute("CombatState", "aggressive")
				end
			end
		end
	end,
	onRemove = function(_target: string, _source: string?, _stacks: number)
		-- No cleanup needed
	end,
}
