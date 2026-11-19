--!strict
-- Scenarios: every scenario from `scenario list` as a row, grouped by the first part of its id
-- ("combat/...", "arena/..."), with the selected one's details, load / pin / exit, and what pressing
-- Play loads, in the detail pane.
--
-- Loading, reloading and leaving all change the one server-wide world, so while any of them is out
-- every load waits.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local Console = script.Parent.Parent
local ConsoleStore = require(Console.ConsoleStore)
local Controls = require(Console.Controls)
local Selection = require(Console.Selection)

local e = React.createElement

local TAB = "scenarios"
local BUSY = "scenario:"
-- Ids without a path go here; scenarios built entirely from a Studio stage carry their own group.
local GENERAL = "general"
local STAGES = "studio stages"

local function groupOf(info: any): string
	local prefix = string.match(info.id, "^(.-)/")
	if prefix then
		return prefix
	end
	return if info.source == "stage" then STAGES else GENERAL
end

local function capitalized(text: string): string
	return string.upper(string.sub(text, 1, 1)) .. string.sub(text, 2)
end

local function bootLabel(pin: string?): string
	if pin == nil then
		return "…"
	elseif pin == "last" then
		return "last loaded"
	elseif pin == "default" then
		return "always default"
	end
	return pin
end

local function loadAction(info: any): (string, string)
	if info.current then
		return "Reload", "scenario reload"
	end
	return "Load", `scenario load {info.id}`
end

local function ScenariosTab(props: { snapshot: ConsoleStore.State })
	local snapshot = props.snapshot
	local list = snapshot.lists.scenarios
	local scenarios: { any } = if list and list.scenarios then list.scenarios else {}
	local bootData = snapshot.lists.boot
	local pin: string? = bootData and bootData.boot
	local busy = ConsoleStore.anyBusy(snapshot, BUSY)

	-- Groups in first-seen order, so "general" (where default sorts) leads.
	local groups: { string } = {}
	local members: { [string]: { any } } = {}
	local current: any? = nil
	for _, info in ipairs(scenarios) do
		local group = groupOf(info)
		if not members[group] then
			members[group] = {}
			table.insert(groups, group)
		end
		table.insert(members[group], info)
		if info.current then
			current = info
		end
	end

	local keys: { string } = {}
	local byId: { [string]: any } = {}
	for _, group in ipairs(groups) do
		for _, info in ipairs(members[group]) do
			table.insert(keys, info.id)
			byId[info.id] = info
		end
	end
	local selectedId = Selection.resolve(snapshot, TAB, keys, current and current.id)
	local selected = selectedId and byId[selectedId]

	local primary: ConsoleStore.Primary? = nil
	if selected then
		local label, command = loadAction(selected)
		primary = {
			label = label,
			command = command,
			options = { key = BUSY .. selected.id, refresh = ConsoleStore.ALL_LISTS },
			enabled = not busy,
		}
	end
	Selection.usePublish(TAB, { keys = keys, selected = selectedId, primary = primary })

	local children: { [string]: any } = {}
	local order = 0
	for _, group in ipairs(groups) do
		order += 1
		children[`g{order}`] = e(Controls.SectionLabel, {
			text = `{capitalized(group)} · {#members[group]}`,
			first = order == 1,
			layoutOrder = order,
		})
		for _, info in ipairs(members[group]) do
			order += 1
			local chips = { if info.stage then info.stage else "baseplate" }
			if info.source == "stage" then
				table.insert(chips, "studio stage")
			elseif info.character ~= "keep" then
				table.insert(chips, info.character)
			end
			if pin == info.id then
				table.insert(chips, "boots")
			end
			children[info.id] = e(Controls.Row, {
				title = info.title,
				dot = if info.current then "on" else nil,
				chips = chips,
				selected = info.id == selectedId,
				onSelect = function()
					ConsoleStore.pick(TAB, info.id)
				end,
				layoutOrder = order,
			})
		end
	end
	if #scenarios == 0 then
		children.Empty = e(Controls.Empty, {
			text = snapshot.listErrors.scenarios or "Reading the scenario list…",
			bad = snapshot.listErrors.scenarios ~= nil,
			layoutOrder = 1,
		})
	end

	local detail: any = nil
	if selected then
		local label = loadAction(selected)
		local pinned = pin == selected.id
		local function boot(choice: string)
			ConsoleStore.run(`scenario boot {choice}`, { key = "boot", refresh = { "boot" } })
		end
		detail = e(Controls.DetailPane, {
			title = selected.title,
			id = selected.id,
			description = selected.description,
			rows = {
				{ "Stage", selected.stage or "baseplate world" },
				{ "Character", if selected.character == "keep" then "keeps yours" else selected.character },
				{ "Source", if selected.source == "stage" then "Studio stage" else "code" },
				{
					"Play loads",
					if bootData and bootData.target then `{bootData.target}  ({bootLabel(pin)})` else bootLabel(pin),
				},
			},
			actions = {
				Load = e(Controls.Button, {
					text = label,
					primary = true,
					kbd = true,
					busy = snapshot.busy[BUSY .. selected.id] or (selected.current and snapshot.busy[BUSY .. "reload"]),
					enabled = not busy,
					layoutOrder = 1,
					onActivated = function()
						local _, command = loadAction(selected)
						ConsoleStore.run(command, { key = BUSY .. selected.id, refresh = ConsoleStore.ALL_LISTS })
					end,
				}),
				Pin = e(Controls.Button, {
					text = if pinned then "Pinned for play" else "Pin for play",
					selected = pinned,
					enabled = not pinned,
					busy = snapshot.busy.boot,
					layoutOrder = 2,
					onActivated = function()
						boot(selected.id)
					end,
				}),
				Exit = e(Controls.Button, {
					text = "Exit scenario",
					enabled = current ~= nil and not busy,
					busy = snapshot.busy[BUSY .. "exit"],
					layoutOrder = 3,
					onActivated = function()
						ConsoleStore.run("scenario exit", { key = BUSY .. "exit", refresh = ConsoleStore.ALL_LISTS })
					end,
				}),
			},
		}, {
			OnPlay = e(Controls.Line, { inset = false, vertical = 0, wrap = true, layoutOrder = 1 }, {
				Label = e(Controls.Text, { text = "On play", tone = "dim", size = 14, width = UDim.new(0, 92), height = 26, layoutOrder = 1 }),
				Last = e(Controls.Chip, {
					text = "Last loaded",
					selected = pin == "last",
					onActivated = function()
						boot("last")
					end,
					layoutOrder = 2,
				}),
				Default = e(Controls.Chip, {
					text = "Always default",
					selected = pin == "default",
					onActivated = function()
						boot("default")
					end,
					layoutOrder = 3,
				}),
				Pinned = if pin and pin ~= "last" and pin ~= "default"
					then e(Controls.Chip, { text = pin, mono = true, selected = true, layoutOrder = 4 })
					else nil,
			}),
			Error = if snapshot.listErrors.boot
				then e(Controls.Result, { result = { ok = false, message = snapshot.listErrors.boot }, layoutOrder = 2 })
				else nil,
		})
	end

	return e(Controls.TabLayout, { detail = detail }, children)
end

return ScenariosTab
