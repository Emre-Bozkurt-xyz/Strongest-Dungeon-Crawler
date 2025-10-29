--!strict
-- EntityUtils: shared helpers for entity (player/NPC) queries

local Players = game:GetService("Players")

local EntityUtils = {}

-- Returns the faction/team for any entity (player or NPC model)
function EntityUtils.getFaction(entity: Instance?): string
	if not entity then
		return "Neutral"
	end
	-- Player
	local plr = nil
	if typeof(entity) == "Instance" and entity:IsA("Player") then
		plr = entity
	elseif typeof(entity) == "Instance" and entity:IsA("Model") then
		plr = Players:GetPlayerFromCharacter(entity)
	end
	if plr then
		-- Prefer Team, fallback to Faction attribute
		if plr.Team and typeof(plr.Team) == "Instance" and plr.Team.Name then
			return tostring(plr.Team.Name)
		end
		local fac = plr:GetAttribute("Faction")
		if type(fac) == "string" then
			return fac
		end
		return "Player"
	end
	-- NPC: look for Faction attribute on model or its parent
	if typeof(entity) == "Instance" and entity:IsA("Model") then
		local fac = entity:GetAttribute("Faction")
		if type(fac) == "string" then
			return fac
		end
		if entity.Parent and entity.Parent:IsA("Model") then
			local pfac = entity.Parent:GetAttribute("Faction")
			if type(pfac) == "string" then
				return pfac
			end
		end
		return "Enemy"
	end
	return "Neutral"
end

return EntityUtils
