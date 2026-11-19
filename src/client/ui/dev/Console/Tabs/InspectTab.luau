--!strict
-- Inspect: one entity's live combat state from the `inspect` command -- stats as base -> final with
-- the modifiers that move them indented under each, status effects, the skill session. The player by
-- default; an NPC when picked here or with Inspect in the World tab.
--
-- The targets are chips pinned above the list (Up/Down walks them); the stats scroll; statuses and
-- the skill session sit in the pinned pane at the foot, so they stay in view while watching a fight
-- however far the stats are scrolled. Read about once a second while the tab is showing, without
-- logging (a read, not an action); Enter runs `inspect` for real, which logs the whole result.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local Console = script.Parent.Parent
local ConsoleStore = require(Console.ConsoleStore)
local Controls = require(Console.Controls)
local Selection = require(Console.Selection)
local Theme = require(Console.Theme)

local client = script:FindFirstAncestor("Client") :: Instance
local DevCommandsClient = require((client :: any).dev.Commands)

local e = React.createElement
local size = Theme.size
local space = Theme.space

local TAB = "inspect"
local POLL_SECONDS = 1
local SELF = "me"

local function fmt(value: any): string
	if type(value) == "number" then
		if value % 1 == 0 then
			return tostring(value)
		end
		return string.format("%.2f", value)
	end
	return tostring(value)
end

local function signed(value: any): string
	if type(value) == "number" and value >= 0 then
		return "+" .. fmt(value)
	end
	return fmt(value)
end

local function StatRow(props: { stat: any, layoutOrder: number })
	local stat = props.stat
	local modified = #stat.modifiers > 0
	local final = if stat.current ~= nil then `{fmt(stat.current)} / {fmt(stat.max)}` else fmt(stat.final)
	local children: { [string]: any } = {
		Layout = Controls.list(Enum.FillDirection.Vertical, 0),
		Line = e(Controls.Line, { layoutOrder = 0, vertical = 3 }, {
			Name = e(Controls.Text, {
				text = stat.name,
				tone = if modified then "text" else "secondary",
				height = 24,
				fill = true,
				layoutOrder = 1,
			}),
			Base = e(Controls.Text, {
				text = fmt(stat.base),
				mono = true,
				size = size.monoSmall,
				tone = "dim",
				height = 24,
				autoWidth = true,
				layoutOrder = 2,
			}),
			Arrow = e(Controls.Text, { text = "→", tone = "dim", size = size.secondary, height = 24, autoWidth = true, layoutOrder = 3 }),
			Final = e(Controls.Text, {
				text = final,
				mono = true,
				size = size.monoSmall,
				tone = if modified then "text" else "secondary",
				height = 24,
				width = UDim.new(0, 92),
				alignX = Enum.TextXAlignment.Right,
				layoutOrder = 4,
			}),
		}),
	}
	for index, modifier in ipairs(stat.modifiers) do
		local source = if modifier.name ~= modifier.source then `{modifier.name} ({modifier.source})` else modifier.source
		children[`m{index}`] = e("Frame", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			LayoutOrder = index,
		}, {
			Padding = e("UIPadding", {
				PaddingLeft = UDim.new(0, space.pad + 14),
				PaddingRight = UDim.new(0, space.pad),
				PaddingBottom = UDim.new(0, 1),
			}),
			Text = e(Controls.Text, {
				text = `{signed(modifier.value)} {modifier.type} · {source}`,
				mono = true,
				size = size.small,
				tone = "secondary",
				wrap = true,
			}),
		})
	end
	return e("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = props.layoutOrder,
	}, children)
end

local function InspectTab(props: { snapshot: ConsoleStore.State, active: boolean })
	local snapshot = props.snapshot
	local target = snapshot.inspectTarget or SELF
	local data, setData = React.useState(nil :: any)
	local problem, setProblem = React.useState(nil :: string?)
	local filter, setFilter = React.useState("")
	local modifiedOnly, setModifiedOnly = React.useState(false)

	React.useEffect(function()
		if not (props.active and snapshot.open) then
			return
		end
		local running = true
		setData(nil)
		setProblem(nil)
		task.spawn(function()
			while running do
				local ok, result = pcall(DevCommandsClient.query, `inspect {Controls.quote(target)}`)
				if not running then
					break
				end
				if ok and result.ok then
					setData(result.data)
					setProblem(nil)
				else
					setProblem(if ok then result.message else tostring(result))
				end
				task.wait(POLL_SECONDS)
			end
		end)
		return function()
			running = false
		end
	end, { props.active, snapshot.open, target } :: { any })

	-- Targets: you, then every NPC with an id. Names that repeat are numbered in list order (entity ids
	-- are GUIDs, far too long for a chip); the selected NPC's id is in the pane below.
	local npcData = snapshot.lists.npcs
	local npcs: { any } = if npcData and npcData.npcs then npcData.npcs else {}
	local nameCount: { [string]: number } = {}
	for _, npc in ipairs(npcs) do
		nameCount[npc.name] = (nameCount[npc.name] or 0) + 1
	end
	local nameSeen: { [string]: number } = {}
	local keys: { string } = { SELF }
	local chips: { [string]: any } = {}
	local function addChip(key: string, label: string, mono: boolean?)
		chips[`t{#keys}`] = e(Controls.Chip, {
			text = label,
			mono = mono,
			selected = key == target,
			layoutOrder = #keys,
			onActivated = function()
				ConsoleStore.setInspectTarget(if key == SELF then nil else key)
			end,
		})
	end
	addChip(SELF, "Me")
	for _, npc in ipairs(npcs) do
		if npc.entityId then
			table.insert(keys, npc.entityId)
			nameSeen[npc.name] = (nameSeen[npc.name] or 0) + 1
			addChip(npc.entityId, if nameCount[npc.name] > 1 then `{npc.name} {nameSeen[npc.name]}` else npc.name)
		end
	end
	if not table.find(keys, target) then
		table.insert(keys, target)
		addChip(target, target, true)
	end

	Selection.usePublish(TAB, {
		keys = keys,
		selected = target,
		primary = { label = "Log it", command = `inspect {Controls.quote(target)}` },
		onSelect = function(key: string)
			ConsoleStore.setInspectTarget(if key == SELF then nil else key)
		end,
	})

	local top = e(Controls.Stack, {}, {
		Label = e(Controls.SectionLabel, { text = "Target", first = true, layoutOrder = 1 }),
		Chips = e(Controls.Line, { wrap = true, gap = 6, vertical = 0, layoutOrder = 2 }, chips),
		Gap = e("Frame", { Size = UDim2.new(1, 0, 0, 6), BackgroundTransparency = 1, LayoutOrder = 3 }),
	})

	local children: { [string]: any } = {}
	if problem then
		children.Problem = e(Controls.Empty, { text = problem, bad = true, layoutOrder = 1 })
	end

	local detail: any = nil
	if data then
		local needle = string.lower(filter)
		local shown = 0
		local rows: { [string]: any } = {}
		for _, stat in ipairs(data.stats or {}) do
			local passes = (needle == "" or string.find(string.lower(stat.name), needle, 1, true) ~= nil)
				and (not modifiedOnly or #stat.modifiers > 0)
			if passes then
				shown += 1
				rows[stat.name] = e(StatRow, { stat = stat, layoutOrder = 10 + shown })
			end
		end
		children.StatsLabel = e(Controls.SectionLabel, {
			text = `Stats · base → final · {shown}`,
			first = true,
			layoutOrder = 2,
			right = {
				Filter = e(Controls.Input, { text = filter, placeholder = "filter", mono = false, width = 110, onChange = setFilter, layoutOrder = 1 }),
				Modified = e(Controls.Chip, {
					text = "Modified",
					selected = modifiedOnly,
					layoutOrder = 2,
					onActivated = function()
						setModifiedOnly(not modifiedOnly)
					end,
				}),
			},
		})
		Controls.mergeInto(children, rows)
		if shown == 0 then
			children.NoStats = e(Controls.Empty, { text = "No stat matches.", layoutOrder = 3 })
		end

		local statuses: { string } = {}
		for _, status in ipairs(data.statuses or {}) do
			table.insert(statuses, `{status.id}{if status.stacks > 1 then ` ×{status.stacks}` else ""}  {fmt(status.remaining)}s`)
		end
		local session = data.session
		local sessionText = if session
			then `{session.skillId} · {session.state}{if session.combo
				then ` · step {session.combo.currentStep} / {session.combo.totalSteps}`
				else ""} · {fmt(session.stateAge)}s`
			else "none"
		detail = e(Controls.DetailPane, {
			title = data.name,
			id = data.entityId,
			rows = {
				{ "Kind", if data.isPlayer then "player" else "NPC" },
				{ "Statuses", if #statuses > 0 then table.concat(statuses, "\n") else "none", #statuses > 0 },
				{ "Skill", sessionText, session ~= nil },
			},
		})
	elseif not problem then
		children.Loading = e(Controls.Empty, { text = "Reading…", layoutOrder = 1 })
	end

	return e(Controls.TabLayout, { top = top, detail = detail }, children)
end

return InspectTab
