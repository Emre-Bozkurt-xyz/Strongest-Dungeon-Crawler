--!strict
-- Commands that move character and mastery progress without earning it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MasteryTracks = require(ReplicatedStorage.Shared.progression.MasteryTracks)
local Support = require(script.Parent.Parent.CommandSupport)

local function trackIds(): { string }
	local ids: { string } = {}
	for _, track in ipairs(MasteryTracks.list()) do
		table.insert(ids, track.id)
	end
	return ids
end

return {
	{
		name = "xp",
		group = "Progression",
		summary = "Add character XP",
		args = {
			{ name = "amount", type = "number", min = 0 },
		},
		run = function(context, args)
			local player = Support.playerEntity(context)
			local characters = Support.load("Progression.CharacterService")
			characters.grant(player, args.amount)
			return `granted {args.amount} XP (character level {characters.getLevel(player)})`
		end,
	},
	{
		name = "mastery",
		group = "Progression",
		summary = "Set one branch of a mastery track to an exact XP value",
		args = {
			{ name = "track", type = "choice", choices = trackIds },
			-- The branch ids are MasteryService's own; they are not exported from it.
			{ name = "branch", type = "choice", choices = { "trunk", "a", "b" } },
			{ name = "xp", type = "number", min = 0 },
		},
		run = function(context, args)
			local player = Support.playerEntity(context)
			local masteries = Support.load("Progression.MasteryService")
			masteries.setBranchXp(player, args.track, args.branch, args.xp)
			return `set {args.track}/{args.branch} to {args.xp} XP, clamped to the branch cap (track level {masteries.getLevel(player, args.track)})`
		end,
	},
}
