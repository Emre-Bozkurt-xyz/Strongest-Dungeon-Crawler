--!strict
-- Mastery: a node search that unlocks what is picked (`character unlock`), then every track on one
-- line each: the attune star, the track level, and trunk / a / b edited in place, in XP or in ranks,
-- each with a raise-to-max button.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local CharacterTab = script.Parent.Parent
local Console = CharacterTab.Parent.Parent
local Controls = require(Console.Controls)
local Theme = require(Console.Theme)
local EditorStore = require(CharacterTab.EditorStore)
local Parts = require(CharacterTab.Parts)

local e = React.createElement
local color = Theme.color
local size = Theme.size
local space = Theme.space

local BRANCHES = { "trunk", "a", "b" }
local FIELD_WIDTH = 66
local NAME_WIDTH = 52
local LEVEL_WIDTH = 48
local GAP = 6

local KIND_WORDS: { [string]: string } = {
	form = "form",
	infusion = "infusion",
	passive = "passive",
	select = "selectable passive",
	attuned = "attuned node",
}

local function capOf(mastery: any, branch: string): number
	return if branch == "trunk" then mastery.trunkCap else mastery.branchCap
end

local function rankOf(mastery: any, branch: string, branches: { [string]: number }): number
	local xp = branches[branch] or 0
	local thresholds = if branch == "trunk" then mastery.trunkRanks else mastery.branchRanks
	if branch ~= "trunk" and (branches.trunk or 0) < mastery.branchEntry then
		return 0
	end
	local rank = 0
	for index, threshold in ipairs(thresholds) do
		if xp >= threshold then
			rank = index
		end
	end
	return rank
end

local function levelOf(mastery: any, total: number): number
	local level = 0
	for index, threshold in ipairs(mastery.levelTotals) do
		if total >= threshold then
			level = index
		end
	end
	return level
end

local function Mastery(props: Parts.SectionProps)
	local editor, schema, state = props.editor, props.schema, props.state
	local mastery = schema.mastery
	local units, setUnits = React.useState("xp")
	local byRank = units == "rank"

	local attunedList: { string } = table.clone(Parts.list(EditorStore.value(editor, "attuned", state.attunement.tracks)))
	local children: { [string]: any } = {}
	local summaryParts: { string } = {}
	local branchesOf: { [string]: { [string]: number } } = {}

	for _, track in ipairs(mastery.tracks) do
		local served = state.masteries[track.id] or {}
		local branches: { [string]: number } = {}
		for _, branch in ipairs(BRANCHES) do
			branches[branch] = EditorStore.value(editor, `mastery.{track.id}.{branch}`, served[branch] or 0)
		end
		branchesOf[track.id] = branches
	end

	-- Node search.
	local items: { Controls.SearchItem } = {}
	for _, node in ipairs(mastery.nodes) do
		local branches = branchesOf[node.track] or {}
		local open = true
		for branch, need in pairs(node.requirement) do
			if (branches[branch] or 0) < need then
				open = false
			end
		end
		if node.branch == "end" and not table.find(attunedList, node.track) then
			open = false
		end
		local trackName = node.track
		table.insert(items, {
			key = node.id,
			label = node.name,
			kind = (KIND_WORDS[node.kind] or node.kind) .. (if open then " · open" else ""),
			detail = `{trackName} {if byRank then node.unlockRank else node.unlockXp}`,
		})
	end
	children.Search = e(Parts.Line, { layoutOrder = 1 }, {
		Search = e(Controls.Search, {
			items = items,
			placeholder = "find a node",
			hint = "unlock a node",
			fill = true,
			maxRows = 8,
			layoutOrder = 1,
			onPick = function(nodeId)
				EditorStore.command(`character unlock {nodeId}`, "unlock")
			end,
		}),
	})

	children.Units = e(Parts.Line, { layoutOrder = 2 }, {
		Note = e(Parts.Note, {
			text = `star = attuned · {#attunedList} of {state.attunement.slots} slots`,
			fill = true,
			layoutOrder = 1,
		}),
		Label = e(Parts.Note, { text = "values in", layoutOrder = 2 }),
		Xp = e(Controls.Chip, {
			text = "XP",
			selected = not byRank,
			layoutOrder = 3,
			onActivated = function()
				setUnits("xp")
			end,
		}),
		Rank = e(Controls.Chip, {
			text = "Rank",
			selected = byRank,
			layoutOrder = 4,
			onActivated = function()
				setUnits("rank")
			end,
		}),
	})

	local function columnLabel(text: string, order: number): any
		return e(Controls.Text, {
			text = text,
			tone = "dim",
			size = size.small,
			height = 18,
			width = UDim.new(0, FIELD_WIDTH),
			layoutOrder = order,
		})
	end
	children.Columns = e(Parts.Line, { gap = GAP, height = 24, layoutOrder = 3 }, {
		Blank = e("Frame", { Size = UDim2.fromOffset(24 + GAP + NAME_WIDTH + GAP + LEVEL_WIDTH - GAP, 18), BackgroundTransparency = 1, LayoutOrder = 0 }),
		Trunk = columnLabel("trunk", 1),
		A = columnLabel("a", 2),
		B = columnLabel("b", 3),
	})

	for index, track in ipairs(mastery.tracks) do
		local branches = branchesOf[track.id]
		local level = levelOf(mastery, (branches.trunk or 0) + (branches.a or 0) + (branches.b or 0))
		local attuned = table.find(attunedList, track.id) ~= nil
		if level > 0 then
			table.insert(summaryParts, `{track.name} {level}`)
		end

		local row: { [string]: any } = {
			Star = e(Controls.IconButton, {
				glyph = "star",
				color = if attuned then color.warn else nil,
				layoutOrder = 0,
				onActivated = function()
					local nextList = table.clone(attunedList)
					local at = table.find(nextList, track.id)
					if at then
						table.remove(nextList, at)
					else
						table.insert(nextList, track.id)
					end
					EditorStore.edit("attuned", nextList, { attuned = nextList }, true)
				end,
			}),
			Name = e(Controls.Text, {
				text = track.name,
				medium = true,
				height = space.control,
				width = UDim.new(0, NAME_WIDTH),
				layoutOrder = 1,
			}),
			Level = e(Controls.Text, {
				text = `LV {level}`,
				mono = true,
				tone = "dim",
				size = size.monoSmall,
				height = space.control,
				width = UDim.new(0, LEVEL_WIDTH - GAP),
				layoutOrder = 2,
			}),
		}
		for branchIndex, branch in ipairs(BRANCHES) do
			local path = `mastery.{track.id}.{branch}`
			local xp = branches[branch] or 0
			local cap = capOf(mastery, branch)
			local text = if xp >= cap
				then "max"
				elseif byRank then tostring(rankOf(mastery, branch, branches))
				else Parts.number(Parts.round(xp))
			local function set(value: any, shownXp: number)
				EditorStore.edit(path, shownXp, { mastery = { [track.id] = { [branch] = value } } })
			end
			row[branch] = e(Controls.Field, {
				value = text,
				width = FIELD_WIDTH,
				invalid = EditorStore.isInvalid(editor, path),
				layoutOrder = 2 + branchIndex,
				onCommit = function(input)
					local lowered = string.lower(input)
					if lowered == "max" or lowered == "mastered" then
						set("mastered", cap)
						return
					end
					local number = tonumber(input)
					if not number or number < 0 then
						return
					end
					if byRank then
						local thresholds = if branch == "trunk" then mastery.trunkRanks else mastery.branchRanks
						local rank = math.floor(number)
						local shownXp = if rank == 0 then 0 else thresholds[rank]
						if shownXp then
							set({ rank = rank }, shownXp)
						else
							set({ rank = rank }, xp)
						end
					else
						set(math.min(number, cap), math.min(number, cap))
					end
				end,
			}, {
				Max = e("Frame", {
					Size = UDim2.fromOffset(18, 18),
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, 4, 0.5, 0),
					BackgroundTransparency = 1,
				}, {
					Button = e(Controls.IconButton, {
						glyph = "max",
						size = 18,
						enabled = xp < cap,
						onActivated = function()
							set("mastered", cap)
						end,
					}),
				}),
			})
		end
		children[`t{index}`] = e(Parts.Line, { gap = GAP, layoutOrder = 10 + index * 2 }, row)
		local problem = EditorStore.errorFor(editor, { `mastery.{track.id}` })
		if problem then
			children[`p{index}`] = e(Parts.Problem, { message = problem, layoutOrder = 11 + index * 2 })
		end
	end
	children.Problem = e(Parts.Problem, { message = EditorStore.errorFor(editor, { "attuned" }), layoutOrder = 100 })
	if editor.notice and editor.notice.key == "unlock" then
		children.Notice = e(Parts.Line, { auto = true, layoutOrder = 101 }, {
			Result = e(Controls.Result, { result = editor.notice, layoutOrder = 1 }),
		})
	end

	return e(Controls.Section, {
		title = "Mastery",
		summary = if #summaryParts > 0 then table.concat(summaryParts, " · ") else "none",
		open = props.open,
		onToggle = props.onToggle,
		layoutOrder = props.layoutOrder,
	}, children)
end

return Mastery
