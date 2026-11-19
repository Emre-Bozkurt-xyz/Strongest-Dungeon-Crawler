--!strict
-- Inspect: one entity's live combat state from the `inspect` command -- stats with the modifiers
-- that move them and where each came from, status effects, the skill session. The player by default;
-- an NPC when picked here or with Inspect on its row in the World tab.
--
-- Read about once a second while the tab is showing, without logging (a read, not an action), so
-- modifiers can be watched coming and going during a fight.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local Console = script.Parent.Parent
local ThemeContext = require(Console.Parent.Parent.hooks.ThemeContext)
local ConsoleStore = require(Console.ConsoleStore)
local Controls = require(Console.Controls)

local client = script:FindFirstAncestor("Client") :: Instance
local DevCommandsClient = require((client :: any).dev.Commands)

local e = React.createElement

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
	local theme = ThemeContext.useTheme()
	local stat = props.stat
	local modified = #stat.modifiers > 0
	local value = if stat.current ~= nil then `{fmt(stat.current)} / {fmt(stat.max)}` else fmt(stat.final)
	local children: { [string]: any } = {
		Line = e(Controls.Row, { layoutOrder = 1, height = 26 }, {
			Name = e(Controls.Label, {
				text = stat.name,
				bold = true,
				height = 26,
				width = UDim.new(0, 0),
				fill = true,
				color = if modified then theme.color.textPrimary else theme.color.textMuted,
				layoutOrder = 1,
			}),
			Base = e(Controls.Label, {
				text = `base {fmt(stat.base)}`,
				mono = true,
				size = Controls.MONO,
				height = 26,
				width = UDim.new(0, 120),
				alignX = Enum.TextXAlignment.Right,
				color = theme.color.textMuted,
				layoutOrder = 2,
			}),
			Final = e(Controls.Label, {
				text = value,
				mono = true,
				size = Controls.MONO,
				height = 26,
				width = UDim.new(0, 130),
				alignX = Enum.TextXAlignment.Right,
				color = if modified then theme.color.accent else theme.color.textPrimary,
				layoutOrder = 3,
			}),
		}),
	}
	for index, modifier in ipairs(stat.modifiers) do
		local label = if modifier.name ~= modifier.source then `{modifier.name}  ({modifier.source})` else modifier.source
		children[`m{index}`] = e(Controls.Row, { layoutOrder = 1 + index, height = 24 }, {
			Indent = e("Frame", { Size = UDim2.fromOffset(14, 1), BackgroundTransparency = 1, LayoutOrder = 0 }),
			Source = e(Controls.Label, {
				text = label,
				size = Controls.SMALL,
				height = 24,
				width = UDim.new(0, 0),
				fill = true,
				color = theme.color.textMuted,
				layoutOrder = 1,
			}),
			Type = e(Controls.Label, {
				text = modifier.type,
				mono = true,
				size = Controls.MONO,
				height = 24,
				autoWidth = true,
				color = theme.color.textMuted,
				layoutOrder = 2,
			}),
			Value = e(Controls.Label, {
				text = signed(modifier.value),
				mono = true,
				size = Controls.MONO,
				height = 24,
				width = UDim.new(0, 90),
				alignX = Enum.TextXAlignment.Right,
				layoutOrder = 3,
			}),
		})
	end
	return e(Controls.Stack, { gap = 0, layoutOrder = props.layoutOrder }, children)
end

local function InspectTab(props: { snapshot: ConsoleStore.State, active: boolean })
	local theme = ThemeContext.useTheme()
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

	local npcData = snapshot.lists.npcs
	local npcChoices: { string } = {}
	local labelToId: { [string]: string } = {}
	for _, npc in ipairs(if npcData and npcData.npcs then npcData.npcs else {}) do
		if npc.entityId then
			local label = `{npc.name}  {npc.entityId}`
			table.insert(npcChoices, label)
			labelToId[label] = npc.entityId
		end
	end
	local currentLabel: string? = nil
	for label, id in pairs(labelToId) do
		if id == target then
			currentLabel = label
		end
	end

	local children: { [string]: any } = {}
	children.Target = e(Controls.Section, { title = "Target", layoutOrder = 1 }, {
		Row = e(Controls.Row, { layoutOrder = 1 }, {
			Me = e(Controls.Button, {
				text = "Me",
				selected = target == SELF,
				layoutOrder = 1,
				onActivated = function()
					ConsoleStore.setInspectTarget(nil)
				end,
			}),
			Npc = e(Controls.Choice, {
				value = currentLabel,
				choices = npcChoices,
				placeholder = if target ~= SELF then target else "an NPC",
				onPick = function(label: string?)
					ConsoleStore.setInspectTarget(if label then labelToId[label] else nil)
				end,
				fill = true,
				layoutOrder = 2,
			}),
		}),
	})

	if problem then
		children.Problem = e(Controls.ResultLine, { result = { ok = false, message = problem }, layoutOrder = 2 })
	end

	if data then
		children.Who = e(Controls.Row, { layoutOrder = 3, gap = 8 }, {
			Name = e(Controls.Label, { text = data.name, bold = true, size = 19, height = 28, autoWidth = true, layoutOrder = 1 }),
			Kind = e(Controls.Chip, { text = if data.isPlayer then "player" else "npc", layoutOrder = 2 }),
			Id = e(Controls.Label, {
				text = data.entityId,
				mono = true,
				size = Controls.MONO,
				height = 28,
				width = UDim.new(0, 0),
				fill = true,
				alignX = Enum.TextXAlignment.Right,
				color = theme.color.textMuted,
				layoutOrder = 3,
			}),
		})

		local session = data.session
		children.Session = e(Controls.Section, { title = "Skill session", layoutOrder = 4 }, {
			Text = e(Controls.Label, {
				text = if session
					then `{session.skillId}  ·  {session.state}{if session.combo
						then `  ·  combo {session.combo.currentStep}/{session.combo.totalSteps}`
						else ""}  ·  {fmt(session.stateAge)}s in state`
					else "No active session.",
				mono = session ~= nil,
				size = if session then Controls.MONO else Controls.TEXT,
				color = if session then theme.color.accent else theme.color.textMuted,
				wrap = true,
				layoutOrder = 1,
			}),
		})

		local statusRows: { [string]: any } = {}
		for index, status in ipairs(data.statuses or {}) do
			statusRows[`s{index}`] = e(Controls.Row, { layoutOrder = index, height = 26 }, {
				Id = e(Controls.Label, { text = status.id, bold = true, height = 26, width = UDim.new(0, 0), fill = true, layoutOrder = 1 }),
				Stacks = e(Controls.Label, { text = `x{status.stacks}`, mono = true, size = Controls.MONO, height = 26, width = UDim.new(0, 60), alignX = Enum.TextXAlignment.Right, layoutOrder = 2 }),
				Left = e(Controls.Label, {
					text = `{fmt(status.remaining)}s`,
					mono = true,
					size = Controls.MONO,
					height = 26,
					width = UDim.new(0, 80),
					alignX = Enum.TextXAlignment.Right,
					color = theme.color.textMuted,
					layoutOrder = 3,
				}),
			})
		end
		if #(data.statuses or {}) == 0 then
			statusRows.None = e(Controls.Label, { text = "No status effects.", color = theme.color.textMuted, layoutOrder = 0 })
		end
		children.Statuses = e(Controls.Section, { title = "Status effects", layoutOrder = 5 }, statusRows)

		local statRows: { [string]: any } = {
			Tools = e(Controls.Row, { layoutOrder = 0 }, {
				Filter = e(Controls.Field, { text = filter, placeholder = "filter stats", fill = true, onChange = setFilter, layoutOrder = 1 }),
				Modified = e(Controls.Button, {
					text = "Modified only",
					selected = modifiedOnly,
					layoutOrder = 2,
					onActivated = function()
						setModifiedOnly(not modifiedOnly)
					end,
				}),
			}),
		}
		local needle = string.lower(filter)
		local shown = 0
		for _, stat in ipairs(data.stats or {}) do
			local passes = (needle == "" or string.find(string.lower(stat.name), needle, 1, true) ~= nil)
				and (not modifiedOnly or #stat.modifiers > 0)
			if passes then
				shown += 1
				statRows[stat.name] = e(StatRow, { stat = stat, layoutOrder = shown })
			end
		end
		children.Stats = e(Controls.Section, { title = `Stats  ({shown})`, layoutOrder = 6 }, statRows)
	elseif not problem then
		children.Loading = e(Controls.Label, { text = "Reading…", color = theme.color.textMuted, layoutOrder = 3 })
	end

	return e(Controls.Stack, { gap = 14 }, children)
end

return InspectTab
