--!strict
-- Scenarios: every scenario from `scenario list`, grouped by the first part of its id
-- ("combat/...", "arena/..."), with what pressing Play loads.
--
-- Loading, reloading and leaving all change the one server-wide world, so while any of them is out
-- every scenario button waits.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local Console = script.Parent.Parent
local ThemeContext = require(Console.Parent.Parent.hooks.ThemeContext)
local ConsoleStore = require(Console.ConsoleStore)
local Controls = require(Console.Controls)

local e = React.createElement

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

local function ScenarioRow(props: { info: any, snapshot: ConsoleStore.State, boot: string?, layoutOrder: number })
	local theme = ThemeContext.useTheme()
	local info = props.info
	local busy = ConsoleStore.anyBusy(props.snapshot, BUSY)
	local key = BUSY .. info.id
	local pinned = props.boot == info.id

	local meta: { string } = {}
	table.insert(meta, if info.stage then `stage {info.stage}` else "baseplate world")
	table.insert(meta, if info.character == "keep" then "keeps your character" else `character {info.character}`)

	return e(Controls.Card, { layoutOrder = props.layoutOrder, current = info.current }, {
		Top = e(Controls.Row, { layoutOrder = 1, gap = 8 }, {
			Title = e(Controls.Label, {
				text = info.title,
				bold = true,
				size = 19,
				height = 28,
				autoWidth = true,
				color = if info.current then theme.color.accent else theme.color.textPrimary,
				layoutOrder = 1,
			}),
			Current = if info.current then e(Controls.Chip, { text = "loaded", color = theme.color.accent, layoutOrder = 2 }) else nil,
			Source = e(Controls.Chip, {
				text = if info.source == "stage" then "studio stage" else "code",
				color = if info.source == "stage" then theme.color.critical else theme.color.textMuted,
				layoutOrder = 3,
			}),
			Pinned = if pinned then e(Controls.Chip, { text = "boots", color = theme.color.textPrimary, layoutOrder = 4 }) else nil,
		}),
		Id = e(Controls.Label, {
			text = info.id,
			mono = true,
			size = Controls.MONO,
			color = theme.color.textMuted,
			layoutOrder = 2,
		}),
		Description = if info.description ~= ""
			then e(Controls.Label, {
				text = info.description,
				size = Controls.SMALL,
				wrap = true,
				layoutOrder = 3,
			})
			else nil,
		Meta = e(Controls.Label, {
			text = table.concat(meta, "  ·  "),
			size = Controls.SMALL,
			color = theme.color.textMuted,
			wrap = true,
			layoutOrder = 4,
		}),
		Actions = e(Controls.Row, { layoutOrder = 5, gap = 6, wrap = true }, {
			Load = e(Controls.Button, {
				text = if info.current then "Reload" else "Load",
				tone = "primary",
				busy = props.snapshot.busy[key],
				enabled = not busy,
				layoutOrder = 1,
				onActivated = function()
					ConsoleStore.run(if info.current then "scenario reload" else `scenario load {info.id}`, {
						key = key,
						refresh = ConsoleStore.ALL_LISTS,
					})
				end,
			}),
			Pin = e(Controls.Button, {
				text = if pinned then "Pinned for Play" else "Pin for Play",
				selected = pinned,
				busy = props.snapshot.busy["boot"],
				enabled = not pinned,
				layoutOrder = 2,
				onActivated = function()
					ConsoleStore.run(`scenario boot {info.id}`, { key = "boot", refresh = { "boot" } })
				end,
			}),
		}),
	})
end

local function ScenariosTab(props: { snapshot: ConsoleStore.State })
	local theme = ThemeContext.useTheme()
	local snapshot = props.snapshot
	local list = snapshot.lists.scenarios
	local scenarios: { any } = if list and list.scenarios then list.scenarios else {}
	local bootData = snapshot.lists.boot
	local pin: string? = bootData and bootData.boot
	local busy = ConsoleStore.anyBusy(snapshot, BUSY)

	local current: any? = nil
	for _, info in ipairs(scenarios) do
		if info.current then
			current = info
		end
	end

	local children: { [string]: any } = {}

	children.Loaded = e(Controls.Section, { title = "Loaded", layoutOrder = 1 }, {
		Now = e(Controls.Label, {
			text = if current then `{current.title}  ({current.id})` else "No scenario is loaded.",
			bold = current ~= nil,
			color = if current then theme.color.textPrimary else theme.color.textMuted,
			layoutOrder = 1,
		}),
		Actions = e(Controls.Row, { layoutOrder = 2, wrap = true }, {
			Reload = e(Controls.Button, {
				text = "Reload",
				enabled = current ~= nil and not busy,
				busy = snapshot.busy[BUSY .. "reload"],
				layoutOrder = 1,
				onActivated = function()
					ConsoleStore.run("scenario reload", { key = BUSY .. "reload", refresh = ConsoleStore.ALL_LISTS })
				end,
			}),
			Default = e(Controls.Button, {
				text = "Load default",
				enabled = not busy,
				busy = snapshot.busy[BUSY .. "default"],
				layoutOrder = 2,
				onActivated = function()
					ConsoleStore.run("scenario load default", { key = BUSY .. "default", refresh = ConsoleStore.ALL_LISTS })
				end,
			}),
			Exit = e(Controls.Button, {
				text = "Exit scenario",
				tone = "danger",
				enabled = current ~= nil and not busy,
				busy = snapshot.busy[BUSY .. "exit"],
				layoutOrder = 3,
				onActivated = function()
					ConsoleStore.run("scenario exit", { key = BUSY .. "exit", refresh = ConsoleStore.ALL_LISTS })
				end,
			}),
		}),
		Note = e(Controls.Label, {
			text = "Exit tears the scenario down, unloads its stage and puts everyone back on their real save at the world spawn.",
			size = Controls.SMALL,
			wrap = true,
			color = theme.color.textMuted,
			layoutOrder = 3,
		}),
	})

	local pinLabel = if pin == nil
		then "…"
		elseif pin == "last" then "the last scenario you loaded"
		elseif pin == "default" then "the default scenario"
		else pin
	children.Boot = e(Controls.Section, { title = "Pressing Play loads", layoutOrder = 2 }, {
		Now = e(Controls.Label, {
			text = if bootData and bootData.target then `{pinLabel}  →  {bootData.target}` else pinLabel,
			mono = pin ~= nil and pin ~= "last" and pin ~= "default",
			layoutOrder = 1,
		}),
		Choices = e(Controls.Row, { layoutOrder = 2 }, {
			Last = e(Controls.Button, {
				text = "Last loaded",
				selected = pin == "last",
				busy = snapshot.busy.boot,
				layoutOrder = 1,
				onActivated = function()
					ConsoleStore.run("scenario boot last", { key = "boot", refresh = { "boot" } })
				end,
			}),
			Default = e(Controls.Button, {
				text = "Always default",
				selected = pin == "default",
				busy = snapshot.busy.boot,
				layoutOrder = 2,
				onActivated = function()
					ConsoleStore.run("scenario boot default", { key = "boot", refresh = { "boot" } })
				end,
			}),
		}),
		Error = if snapshot.listErrors.boot
			then e(Controls.ResultLine, { result = { ok = false, message = snapshot.listErrors.boot }, layoutOrder = 3 })
			else nil,
	})

	-- Groups in first-seen order, so "general" (where default sorts) leads.
	local groups: { string } = {}
	local members: { [string]: { any } } = {}
	for _, info in ipairs(scenarios) do
		local group = groupOf(info)
		if not members[group] then
			members[group] = {}
			table.insert(groups, group)
		end
		table.insert(members[group], info)
	end

	for groupIndex, group in ipairs(groups) do
		local rows: { [string]: any } = {}
		for index, info in ipairs(members[group]) do
			rows[`s{index}`] = e(ScenarioRow, {
				info = info,
				snapshot = snapshot,
				boot = pin,
				layoutOrder = index,
			})
		end
		children[`g{groupIndex}`] = e(Controls.Section, {
			title = `{group}  ({#members[group]})`,
			layoutOrder = 10 + groupIndex,
		}, rows)
	end

	if #scenarios == 0 then
		children.Empty = e(Controls.Label, {
			text = snapshot.listErrors.scenarios or "Reading the scenario list…",
			color = if snapshot.listErrors.scenarios then theme.color.danger else theme.color.textMuted,
			wrap = true,
			layoutOrder = 10,
		})
	end

	return e(Controls.Stack, { gap = 14 }, children)
end

return ScenariosTab
