--!strict
-- Character: an editor over the whole live character, applied as it is edited.
--
-- Pinned at the top, the line "Editing [base ▾] · n edits · Presets": the base is the preset the
-- build came from (or the real save), and picking another applies it. Below, an accordion of nine
-- sections (level, attributes, pools, mastery, skills and bar, equipment, bag, form and passives,
-- base stat overrides), each summed up in one line while closed; it scrolls. Pinned at the foot,
-- the save pane: what was edited, a name, Save preset, Revert, Copy source, Restore real save.
--
-- Every change applies at once through EditorStore (one `character set` patch per settled change)
-- on a sandbox copy: on the real save, the first edit moves the player onto a copy of their build,
-- so the real profile is never written. Presets swaps the accordion for the preset list.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local Console = script.Parent.Parent
local ConsoleStore = require(Console.ConsoleStore)
local Controls = require(Console.Controls)
local Selection = require(Console.Selection)
local Theme = require(Console.Theme)
local EditorStore = require(script.EditorStore)
local PresetList = require(script.PresetList)

local Sections = script.Sections
local SECTIONS: { { id: string, component: any } } = {
	{ id = "level", component = require(Sections.Level) },
	{ id = "attributes", component = require(Sections.Attributes) },
	{ id = "pools", component = require(Sections.Pools) },
	{ id = "mastery", component = require(Sections.Mastery) },
	{ id = "skills", component = require(Sections.Skills) },
	{ id = "equipment", component = require(Sections.Equipment) },
	{ id = "bag", component = require(Sections.Bag) },
	{ id = "forms", component = require(Sections.Forms) },
	{ id = "stats", component = require(Sections.Stats) },
}

local e = React.createElement
local size = Theme.size

local TAB = "character"
local REAL = "real save"
local NAME_PATTERN = "^[%w_%-]+$"

local function useEditor(): EditorStore.State
	local snapshot, setSnapshot = React.useState(EditorStore.get)
	React.useEffect(function()
		local stop = EditorStore.subscribe(function()
			setSnapshot(EditorStore.get())
		end)
		setSnapshot(EditorStore.get())
		return stop
	end, {})
	return snapshot
end

-- Marks the editor's root as the scope Tab walks fields in.
local function markScope(instance: Instance?)
	if instance then
		instance:SetAttribute(Controls.FIELD_SCOPE, true)
	end
end

local function buildHeader(props: { snapshot: ConsoleStore.State, editor: EditorStore.State }): (any, { [string]: boolean })
	local snapshot, editor = props.snapshot, props.editor
	local state = editor.state
	local list = snapshot.lists.presets
	local presets: { any } = if list and list.presets then list.presets else {}
	local sandboxed = state ~= nil and state.sandboxed == true
	local edits = if state then #state.edited else 0

	local choices: { string } = { REAL }
	local labels: { [string]: string } = {}
	local fileNames: { [string]: boolean } = {}
	for _, preset in ipairs(presets) do
		table.insert(choices, preset.name)
		if preset.source == "saved" then
			labels[preset.name] = `{preset.name} · saved`
		elseif preset.source == "session" then
			labels[preset.name] = `{preset.name} · this session`
		else
			fileNames[preset.name] = true
		end
	end
	local value = if not state then nil elseif not sandboxed then REAL else state.name

	local note: string
	local tone: Controls.Tone = "dim"
	if not state then
		note = editor.stateError or "Reading your character…"
		tone = if editor.stateError then "bad" else "dim"
	elseif not sandboxed then
		note = "Your real save · the first edit moves you onto a sandbox copy of it"
	elseif state.base == "" then
		note = "A sandbox copy of your real save · changes apply to you live"
	else
		note = "Changes apply to you live, on a sandbox copy"
	end
	local notice = editor.notice
	local failed = if notice and not notice.ok and notice.key ~= "unlock" then notice else nil
	local general = if editor.failure and #editor.failure.problems == 0 then editor.failure.message else nil

	return e(Controls.Stack, { gap = 0 }, {
		Line = e(Controls.Line, { layoutOrder = 1, vertical = 8 }, {
			Label = e(Controls.Text, { text = "Editing", tone = "secondary", size = size.secondary, height = 28, autoWidth = true, layoutOrder = 1 }),
			Base = e(Controls.Select, {
				value = value,
				choices = choices,
				labels = labels,
				placeholder = "…",
				fill = true,
				layoutOrder = 2,
				onPick = function(pick)
					if not pick or pick == value then
						return
					end
					if pick == REAL then
						EditorStore.command("character restore", "restore")
					else
						EditorStore.command(`character apply {pick}`, pick)
					end
				end,
			}),
			Edits = if edits > 0
				then e(Controls.Chip, { text = `{edits} {if edits == 1 then "edit" else "edits"}`, tone = "warn", layoutOrder = 3 })
				else nil,
			Busy = if editor.sending then e(Controls.Text, { text = "applying…", tone = "dim", size = size.small, height = 28, autoWidth = true, layoutOrder = 4 }) else nil,
			Presets = e(Controls.Button, {
				text = if editor.view == "presets" then "Editor" else "Presets",
				selected = editor.view == "presets",
				layoutOrder = 6,
				onActivated = function()
					EditorStore.setView(if editor.view == "presets" then "editor" else "presets")
				end,
			}),
		}),
		Note = e(Controls.Stack, { pad = true, layoutOrder = 2 }, {
			Text = e(Controls.Text, { text = note, tone = tone, size = size.secondary, wrap = true, layoutOrder = 1 }),
			Failed = if failed then e(Controls.Result, { result = failed, layoutOrder = 2 }) else nil,
			General = if general then e(Controls.Result, { result = { ok = false, message = general }, layoutOrder = 3 }) else nil,
			Bottom = e("Frame", { Size = UDim2.fromOffset(1, 6), BackgroundTransparency = 1, LayoutOrder = 4 }),
		}),
		Rule = e(Controls.Divider, { layoutOrder = 3 }),
	}), fileNames
end

local function SavePane(props: { snapshot: ConsoleStore.State, editor: EditorStore.State, fileNames: { [string]: boolean } })
	local snapshot, editor = props.snapshot, props.editor
	local state = editor.state
	local name, setName = React.useState(nil :: string?)
	local sandboxed = state.sandboxed == true
	local busy = ConsoleStore.anyBusy(snapshot, "character:")

	-- A new name by default, so saving never overwrites a preset by accident: the base's root with
	-- "-edit", numbered past any name already taken.
	local list = snapshot.lists.presets
	local existing: { [string]: boolean } = {}
	for _, preset in ipairs(if list and list.presets then list.presets else {}) do
		existing[preset.name] = true
	end
	local first = if state.base ~= "" and state.base ~= "custom"
		then (string.gsub(state.base, "%-edit%-?%d*$", "")) .. "-edit"
		else "my-build"
	local default = first
	local suffix = 2
	while existing[default] do
		default = `{first}-{suffix}`
		suffix += 1
	end
	local typed = name or default
	local valid = string.match(typed, NAME_PATTERN) ~= nil
	local taken = props.fileNames[typed] == true

	local summary = if #state.edited > 0
		then `Edited: {state.editedSummary}`
		elseif sandboxed then `No edits since {state.name}`
		else "On your real save · nothing edited"

	local notice = editor.notice
	local saved = if notice and notice.key == "save" then notice else nil

	local function save()
		if valid and not taken then
			EditorStore.command(`character save {typed}`, "save", function(result)
				if result.ok then
					setName(nil)
				end
			end)
		end
	end

	return e(Controls.Stack, { pad = true, gap = 8 }, {
		Top = e("Frame", { Size = UDim2.fromOffset(1, 4), BackgroundTransparency = 1, LayoutOrder = 0 }),
		Summary = e(Controls.Text, { text = summary, tone = "secondary", size = size.secondary, wrap = true, layoutOrder = 1 }),
		Save = e(Controls.Line, { inset = false, vertical = 0, wrap = true, layoutOrder = 2 }, {
			Name = e(Controls.Field, {
				value = typed,
				width = 150,
				invalid = not valid or taken,
				mono = true,
				layoutOrder = 1,
				onCommit = function(text)
					setName(text)
				end,
			}),
			Save = e(Controls.Button, {
				text = "Save preset",
				primary = true,
				enabled = valid and not taken and not busy,
				busy = snapshot.busy["character:save"],
				layoutOrder = 2,
				onActivated = save,
			}),
			Revert = e(Controls.Button, {
				text = "Revert",
				enabled = sandboxed and not busy and (#state.edited > 0 or state.base == ""),
				busy = snapshot.busy["character:revert"],
				layoutOrder = 3,
				onActivated = function()
					EditorStore.command("character revert", "revert")
				end,
			}),
			Copy = e(Controls.Button, {
				text = if editor.source then "Hide source" else "Copy source",
				busy = snapshot.busy["character:source"],
				layoutOrder = 4,
				onActivated = function()
					if editor.source then
						EditorStore.setSource(nil)
					else
						EditorStore.command("character show", "source", function(result)
							if result.ok and result.data then
								EditorStore.setSource(result.data.source)
							end
						end)
					end
				end,
			}),
			Restore = e(Controls.Button, {
				text = "Restore real save",
				enabled = sandboxed and not busy,
				busy = snapshot.busy["character:restore"],
				layoutOrder = 5,
				onActivated = function()
					EditorStore.command("character restore", "restore")
				end,
			}),
		}),
		Rule = if not valid or taken
			then e(Controls.Text, {
				text = if taken then `'{typed}' is a file preset; pick another name` else "A preset name is letters, digits, - and _.",
				tone = "bad",
				size = size.secondary,
				wrap = true,
				layoutOrder = 3,
			})
			else nil,
		Saved = if saved then e(Controls.Result, { result = saved, layoutOrder = 4 }) else nil,
		Source = if editor.source then e(Controls.CodeView, { text = editor.source, height = 200, layoutOrder = 5 }) else nil,
		SourceHint = if editor.source
			then e(Controls.Text, {
				text = "Click the source, then Ctrl+A, Ctrl+C. Paste it into Presets/<name>.luau to keep it as a file.",
				tone = "dim",
				size = size.small,
				wrap = true,
				layoutOrder = 6,
			})
			else nil,
		Bottom = e("Frame", { Size = UDim2.fromOffset(1, 6), BackgroundTransparency = 1, LayoutOrder = 10 }),
	})
end

local function EditorView(props: { snapshot: ConsoleStore.State, editor: EditorStore.State, top: any, fileNames: { [string]: boolean } })
	local snapshot, editor = props.snapshot, props.editor
	-- No selectable rows here: Up/Down and Enter on the command line do nothing in the editor.
	Selection.usePublish(TAB, { keys = {} })

	local schema, state = editor.schema, editor.state
	if not schema or not state then
		local message = editor.schemaError or editor.stateError
		return e(Controls.TabLayout, { top = props.top }, {
			Empty = e(Controls.Empty, { text = message or "Reading the character…", bad = message ~= nil }),
		})
	end

	local children: { [string]: any } = {}
	for index, section in ipairs(SECTIONS) do
		local open = editor.sections[section.id] == true
		children[section.id] = e(section.component, {
			editor = editor,
			schema = schema,
			state = state,
			open = open,
			layoutOrder = index,
			onToggle = function()
				EditorStore.setSection(section.id, not open)
			end,
		})
	end
	children.End = e(Controls.Divider, { layoutOrder = 100 })

	return e("Frame", { ref = markScope, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, {
		Layout = e(Controls.TabLayout, {
			top = props.top,
			detail = e(SavePane, { snapshot = snapshot, editor = editor, fileNames = props.fileNames }),
		}, children),
	})
end

local function CharacterTab(props: { snapshot: ConsoleStore.State, active: boolean })
	local snapshot = props.snapshot
	local editor = useEditor()

	React.useEffect(function()
		if props.active and snapshot.open then
			return EditorStore.live()
		end
		return nil
	end, { props.active, snapshot.open } :: { any })

	local top, fileNames = buildHeader({ snapshot = snapshot, editor = editor })
	if editor.view == "presets" then
		return e(PresetList, { snapshot = snapshot, editor = editor, top = top })
	end
	return e(EditorView, { snapshot = snapshot, editor = editor, top = top, fileNames = fileNames })
end

return CharacterTab
