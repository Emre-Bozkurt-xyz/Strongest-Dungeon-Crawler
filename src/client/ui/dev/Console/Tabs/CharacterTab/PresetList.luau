--!strict
-- The preset list, the editor's secondary view: every preset as a row (file, saved, or kept for this
-- session), with Apply, View source and, for saved ones, Delete in the detail pane. Its rows are the
-- tab's selectable rows, so Up/Down and Enter on the command line work here as in other tabs.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local CharacterTab = script.Parent
local Console = CharacterTab.Parent.Parent
local ConsoleStore = require(Console.ConsoleStore)
local Controls = require(Console.Controls)
local Selection = require(Console.Selection)
local Theme = require(Console.Theme)
local EditorStore = require(CharacterTab.EditorStore)

local e = React.createElement
local size = Theme.size

local TAB = "character"
local BUSY = "character:"

local SOURCE_WORDS: { [string]: string } = {
	file = "file",
	saved = "saved",
	session = "this session only",
}

local function PresetList(props: { snapshot: ConsoleStore.State, editor: EditorStore.State, top: any })
	local snapshot, editor = props.snapshot, props.editor
	local list = snapshot.lists.presets
	local presets: { any } = if list and list.presets then list.presets else {}
	local sandboxed = snapshot.devCharacter ~= ""
	local busy = ConsoleStore.anyBusy(snapshot, BUSY)
	local shown, setShown = React.useState(nil :: { name: string, source: string }?)

	local keys: { string } = {}
	local byName: { [string]: any } = {}
	local current: string? = nil
	for _, preset in ipairs(presets) do
		table.insert(keys, preset.name)
		byName[preset.name] = preset
		if preset.current then
			current = preset.name
		end
	end
	local selectedName = Selection.resolve(snapshot, TAB, keys, current)
	local selected = selectedName and byName[selectedName]

	local function apply(preset: any)
		EditorStore.command(`character apply {preset.name}`, preset.name)
	end
	local primary: ConsoleStore.Primary? = if selected
		then {
			label = if selected.current then "Re-apply" else "Apply",
			command = `character apply {selected.name}`,
			options = { key = BUSY .. selected.name, refresh = { "presets" } },
			enabled = not busy,
		}
		else nil
	Selection.usePublish(TAB, { keys = keys, selected = selectedName, primary = primary })

	local children: { [string]: any } = {}
	children.Label = e(Controls.SectionLabel, { text = `Presets · {#presets}`, first = true, layoutOrder = 1 })
	for index, preset in ipairs(presets) do
		children[`p{index}`] = e(Controls.Row, {
			title = preset.name,
			dot = if preset.current then "on" else nil,
			chips = if preset.source ~= "file" then { SOURCE_WORDS[preset.source] or preset.source } else nil,
			selected = preset.name == selectedName,
			onSelect = function()
				ConsoleStore.pick(TAB, preset.name)
			end,
			layoutOrder = 1 + index,
		})
	end
	if #presets == 0 then
		children.Empty = e(Controls.Empty, {
			text = snapshot.listErrors.presets or "Reading presets…",
			bad = snapshot.listErrors.presets ~= nil,
			layoutOrder = 2,
		})
	end
	local store = list and list.store
	if store and store.persists == false then
		children.Store = e(Controls.Empty, {
			text = `Saved presets are kept for this session only: {store.reason or "the preset store is unavailable"}`,
			layoutOrder = 500,
		})
	end
	if shown then
		children.SourceLabel = e(Controls.SectionLabel, {
			text = `Source · {shown.name}`,
			layoutOrder = 600,
			right = {
				Hide = e(Controls.Button, {
					text = "Hide",
					onActivated = function()
						setShown(nil)
					end,
				}),
			},
		})
		children.Source = e(Controls.Stack, { pad = true, layoutOrder = 601 }, {
			Code = e(Controls.CodeView, { text = shown.source, height = 260 }),
			Hint = e(Controls.Text, {
				text = "Click the source, then Ctrl+A, Ctrl+C to copy it.",
				tone = "dim",
				size = size.secondary,
				wrap = true,
				layoutOrder = 2,
			}),
		})
	end

	local detail: any = nil
	if selected then
		local preset = selected
		local deletable = preset.source == "saved" or preset.source == "session"
		local notice = editor.notice
		detail = e(Controls.DetailPane, {
			title = preset.name,
			id = if preset.source == "file" then `Presets/{preset.name}.luau` else SOURCE_WORDS[preset.source],
			rows = {
				{ "Source", if preset.source == "file" then "file" elseif preset.source == "saved" then "preset store (kept between sessions)" else "this session only" },
				{ "State", if preset.current then "applied" elseif sandboxed then "not applied" else "not applied · on your real save" },
			},
			children = if notice and notice.key and (notice.key == preset.name or notice.key == "delete:" .. preset.name)
				then { Result = e(Controls.Result, { result = notice }) }
				else nil,
			actions = {
				Apply = e(Controls.Button, {
					text = if preset.current then "Re-apply" else "Apply",
					primary = true,
					kbd = true,
					busy = snapshot.busy[BUSY .. preset.name],
					enabled = not busy,
					layoutOrder = 1,
					onActivated = function()
						apply(preset)
					end,
				}),
				Show = e(Controls.Button, {
					text = "View source",
					busy = snapshot.busy[BUSY .. "show"],
					layoutOrder = 2,
					onActivated = function()
						EditorStore.command(`character show {preset.name}`, "show", function(result)
							if result.ok and result.data then
								setShown({ name = preset.name, source = result.data.source })
							end
						end)
					end,
				}),
				Delete = if deletable
					then e(Controls.Button, {
						text = "Delete",
						busy = snapshot.busy[BUSY .. "delete:" .. preset.name],
						enabled = not busy,
						layoutOrder = 3,
						onActivated = function()
							EditorStore.command(`character delete {preset.name}`, "delete:" .. preset.name, function(result)
								if result.ok and shown and shown.name == preset.name then
									setShown(nil)
								end
							end)
						end,
					})
					else nil,
			},
		})
	end

	return e(Controls.TabLayout, { top = props.top, detail = detail }, children)
end

return PresetList
