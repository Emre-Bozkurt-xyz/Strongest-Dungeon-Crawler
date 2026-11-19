--!strict
-- A tab's selectable rows, wired to the command line: returns the selected key and publishes the
-- tab's view (rows in order, selection, primary action) to ConsoleStore after every render, so
-- Up/Down, Enter on an empty line and the ghost command always act on what is on screen.
--
-- The selection is the stored pick when that row still exists, else `fallback` (a tab's natural
-- default, such as the loaded scenario), else the first row. The fallback is never written back, so
-- a list that changes under the selection settles on its default instead of a stale key.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ConsoleStore = require(script.Parent.ConsoleStore)

local Selection = {}

function Selection.resolve(snapshot: ConsoleStore.State, tab: string, keys: { string }, fallback: string?, noDefault: boolean?): string?
	local picked = snapshot.selection[tab]
	if picked and table.find(keys, picked) then
		return picked
	end
	if noDefault then
		return nil
	end
	if fallback and table.find(keys, fallback) then
		return fallback
	end
	return keys[1]
end

function Selection.usePublish(tab: string, view: ConsoleStore.View)
	React.useEffect(function()
		ConsoleStore.publishView(tab, view)
	end)
end

return Selection
