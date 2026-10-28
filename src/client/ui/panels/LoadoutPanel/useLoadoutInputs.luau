--!strict
-- What both Loadout panels select from (selectors/loadout), for the set being edited.
--
-- Re-renders when the slots, the known skills or their numbers change: none of them is a React store,
-- and each signal only says that something changed.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

local SkillSlots = require(script.Parent.Parent.Parent.Parent.SkillsFramework.SkillSlots)
local SkillsClient = require(script.Parent.Parent.Parent.Parent.SkillsFramework.SkillsClient)
local SkillMetadataClient = require(script.Parent.Parent.Parent.Parent.SkillsFramework.SkillMetadataClient)
local ProgressionClient = require(script.Parent.Parent.Parent.Parent.Progression.ProgressionClient)
local useCombatLoadout = require(script.Parent.Parent.Parent.hooks.useCombatLoadout)
local useProgression = require(script.Parent.Parent.Parent.hooks.useProgression)
local Selector = require(script.Parent.Parent.Parent.selectors.loadout)

local function useSkillStores()
	local _, bump = React.useReducer(function(count: number)
		return count + 1
	end, 0)
	React.useEffect(function()
		local function changed()
			bump(nil)
		end
		local offs = {
			SkillSlots.onSlotsChanged(changed),
			SkillSlots.onActiveSetChanged(changed),
			SkillsClient.onKnownChanged(changed),
			SkillMetadataClient.onChanged(changed),
		}
		return function()
			for _, off in ipairs(offs) do
				off()
			end
		end
	end, {})
end

local function useLoadoutInputs(editingSet: number): Selector.Inputs
	useSkillStores()
	local combat = useCombatLoadout()
	-- Mastery levels and attunement order the skills, so a change to either re-renders.
	useProgression()
	return {
		known = SkillsClient.known(),
		slots = SkillSlots.getSet(editingSet),
		limits = SkillSlots.limits(),
		combat = combat,
		levelOf = ProgressionClient.level,
		attuned = ProgressionClient.attunement(),
	}
end

return useLoadoutInputs
