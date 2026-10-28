--!strict
-- Every screen-space element, declared in one place. The HUD counterpart to PanelRegistry.
--
-- Screen UI needs far less machinery than a world panel: there is no part, no SurfaceGui, no
-- placement and no fade to own, so there is no host. Everything mounts into the one persistent
-- ScreenRoot tree and decides for itself whether to render, which is what React is good at.
--
-- That is the whole reason this is a separate registry rather than a flag on PanelEntry: a world
-- panel's visibility is imperative (a surface exists or it does not), a screen element's is just a
-- render decision.

export type ScreenEntry = {
	id: string,
	component: any,
	-- Painter's order within the ScreenRoot. Higher sits on top.
	zIndex: number?,
}

local RunService = game:GetService("RunService")

local SkillSlotContainer = require(script.Parent.Parent.panels.SkillSlotContainer)
local VitalsHud = require(script.Parent.Parent.panels.VitalsHud)
local NearbyLoot = require(script.Parent.Parent.panels.NearbyLoot)
local Notifications = require(script.Parent.Parent.panels.Notifications)
local EnemyBars = require(script.Parent.Parent.panels.EnemyBars)
local MasteryCanvas = require(script.Parent.Parent.panels.MasteryCanvas)

local entries: { ScreenEntry } = {
	-- First, so the player's own readouts draw over a crowd of enemy bars.
	{
		id = "EnemyBars",
		component = EnemyBars,
	},
	{
		id = "SkillSlotContainer",
		component = SkillSlotContainer,
	},
	{
		id = "VitalsHud",
		component = VitalsHud,
	},
	{
		id = "NearbyLoot",
		component = NearbyLoot,
	},
	-- Over the whole HUD, which it dims, but under the notices so a mastery-up shows on top.
	{
		id = "MasteryCanvas",
		component = MasteryCanvas,
		zIndex = 40,
	},
	{
		id = "Notifications",
		component = Notifications,
		zIndex = 50,
	},
}

-- Dev tooling, never shipped to players.
if RunService:IsStudio() then
	table.insert(entries, {
		id = "StageTuner",
		component = require(script.Parent.Parent.dev.StageTuner),
		zIndex = 100,
	})
end

local ScreenRegistry = {}

function ScreenRegistry.list(): { ScreenEntry }
	return entries
end

function ScreenRegistry.get(id: string): ScreenEntry?
	for _, entry in ipairs(entries) do
		if entry.id == id then
			return entry
		end
	end
	return nil
end

return ScreenRegistry
