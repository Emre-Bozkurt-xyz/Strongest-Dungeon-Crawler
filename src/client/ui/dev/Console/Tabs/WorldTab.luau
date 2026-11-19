--!strict
-- World: the stages, the markers (chips that teleport), a one-line spawn form, and the NPCs in the
-- world. Stages and NPCs are the selectable rows; the detail pane acts on the selected one (load a
-- map; hit, apply a status, inspect or despawn an NPC).
--
-- The NPC list is read again every second or so while this tab is showing, so health and deaths
-- follow what happens in front of the developer. NPC actions address an NPC by its entity id, which
-- `hit` and `status` accept as well as a name, so the NPC acted on is the one selected even among
-- several of the same kind. `despawn` takes a kind (or all), so the pane offers that kind.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local Console = script.Parent.Parent
local ConsoleStore = require(Console.ConsoleStore)
local Controls = require(Console.Controls)
local Selection = require(Console.Selection)
local Theme = require(Console.Theme)

local e = React.createElement
local color = Theme.color
local size = Theme.size

local TAB = "world"
local NPC_POLL_SECONDS = 1.2

local function round(value: number): number
	return math.floor(value + 0.5)
end

-- Repeated marker names become one chip with a count, in first-seen order.
local function grouped(names: { string }, skip: { string }?): { { name: string, count: number } }
	local out: { { name: string, count: number } } = {}
	local index: { [string]: number } = {}
	for _, name in ipairs(names) do
		if not (skip and table.find(skip, name)) then
			if index[name] then
				out[index[name]].count += 1
			else
				table.insert(out, { name = name, count = 1 })
				index[name] = #out
			end
		end
	end
	return out
end

local function npcTarget(npc: any): string
	return npc.entityId or npc.name
end

local function WorldTab(props: { snapshot: ConsoleStore.State, active: boolean })
	local snapshot = props.snapshot
	local stagesData = snapshot.lists.stages
	local stages: { any } = if stagesData and stagesData.stages then stagesData.stages else {}
	local markers = snapshot.lists.markers or {}
	local npcData = snapshot.lists.npcs
	local npcs: { any } = if npcData and npcData.npcs then npcData.npcs else {}
	local kinds = ConsoleStore.choices("spawn", "kind")
	local stageBusy = ConsoleStore.anyBusy(snapshot, "stage:")

	local spawnKind, setSpawnKind = React.useState(nil :: string?)
	local spawnCount, setSpawnCount = React.useState("1")
	local areaLevel, setAreaLevel = React.useState("")
	local rank, setRank = React.useState("")
	local hitAmount, setHitAmount = React.useState("25")
	local effect, setEffect = React.useState(nil :: string?)

	React.useEffect(function()
		if not (props.active and snapshot.open) then
			return
		end
		local running = true
		task.spawn(function()
			while running do
				ConsoleStore.fetch("npcs")
				task.wait(NPC_POLL_SECONDS)
			end
		end)
		return function()
			running = false
		end
	end, { props.active, snapshot.open } :: { any })

	-- Selectable rows: stages, then NPCs.
	local keys: { string } = {}
	local currentStageKey: string? = nil
	for _, stage in ipairs(stages) do
		table.insert(keys, "stage:" .. stage.name)
		if stage.current then
			currentStageKey = "stage:" .. stage.name
		end
	end
	for _, npc in ipairs(npcs) do
		table.insert(keys, "npc:" .. npcTarget(npc))
	end
	local firstNpc = if npcs[1] then "npc:" .. npcTarget(npcs[1]) else nil
	local selectedKey = Selection.resolve(snapshot, TAB, keys, firstNpc or currentStageKey)

	local selectedStage: any? = nil
	local selectedNpc: any? = nil
	if selectedKey then
		for _, stage in ipairs(stages) do
			if "stage:" .. stage.name == selectedKey then
				selectedStage = stage
			end
		end
		for _, npc in ipairs(npcs) do
			if "npc:" .. npcTarget(npc) == selectedKey then
				selectedNpc = npc
			end
		end
	end

	local markerCount = #(markers.stageMarkers or {})

	local function stageLoad(stage: any): (string, string)
		local label = if stage.current then "Reload map" else "Load map"
		return label, `stage load {Controls.quote(stage.name)}`
	end
	local stageRefresh: { ConsoleStore.ListName } = { "stages", "markers", "scenarios" }

	local primary: ConsoleStore.Primary? = nil
	if selectedStage then
		local label, command = stageLoad(selectedStage)
		primary = {
			label = label,
			command = command,
			options = { key = "stage:" .. selectedStage.name, refresh = stageRefresh },
			enabled = not stageBusy,
		}
	elseif selectedNpc then
		local target = npcTarget(selectedNpc)
		local amountOk = tonumber(hitAmount) ~= nil
		primary = {
			label = "Hit",
			command = if amountOk then `hit {Controls.quote(target)} {hitAmount}` else nil,
			fill = `hit {Controls.quote(target)} `,
			options = { key = "hit:" .. target, refresh = { "npcs" } },
			enabled = not selectedNpc.dead and amountOk,
		}
	end
	Selection.usePublish(TAB, { keys = keys, selected = selectedKey, primary = primary })

	local children: { [string]: any } = {}

	-- Stages.
	children.StageLabel = e(Controls.SectionLabel, { text = "Stage", first = true, layoutOrder = 1 })
	for index, stage in ipairs(stages) do
		local key = "stage:" .. stage.name
		children[`s{index}`] = e(Controls.Row, {
			title = stage.name,
			dot = if stage.current then "on" else nil,
			chips = if stage.current then { `{markerCount} markers` } else nil,
			selected = key == selectedKey,
			onSelect = function()
				ConsoleStore.pick(TAB, key)
			end,
			layoutOrder = 1 + index,
		})
	end
	if #stages == 0 then
		children.StageEmpty = e(Controls.Empty, {
			text = snapshot.listErrors.stages or "No stages in ServerStorage.Scenarios.",
			bad = snapshot.listErrors.stages ~= nil,
			layoutOrder = 2,
		})
	end

	-- Markers.
	children.MarkerLabel = e(Controls.SectionLabel, {
		text = "Markers · click to teleport",
		layoutOrder = 100,
		right = {
			Show = e(Controls.Text, { text = "show", tone = "dim", size = size.secondary, height = 24, autoWidth = true, layoutOrder = 1 }),
			Switch = e(Controls.Switch, {
				value = markers.visible == true,
				busy = snapshot.busy.markers,
				layoutOrder = 2,
				onToggle = function()
					ConsoleStore.run(if markers.visible then "markers hide" else "markers show", {
						key = "markers",
						refresh = { "markers" },
					})
				end,
			}),
		},
	})
	local function markerChips(groups: { { name: string, count: number } }, prefix: string, into: { [string]: any })
		for index, group in ipairs(groups) do
			into[`{prefix}{index}`] = e(Controls.Chip, {
				text = if group.count > 1 then `{group.name} ×{group.count}` else group.name,
				busy = snapshot.busy["tp:" .. group.name],
				layoutOrder = 10 + index,
				onActivated = function()
					ConsoleStore.run(`tp {Controls.quote(group.name)}`, { key = "tp:" .. group.name })
				end,
			})
		end
	end
	local stageChips: { [string]: any } = {
		Start = e(Controls.Chip, {
			text = "Start",
			busy = snapshot.busy["tp:start"],
			layoutOrder = 1,
			onActivated = function()
				ConsoleStore.run("tp start", { key = "tp:start" })
			end,
		}),
	}
	markerChips(grouped(markers.stageMarkers or {}), "m", stageChips)
	children.Markers = e(Controls.Line, { wrap = true, gap = 6, layoutOrder = 101 }, stageChips)
	local worldGroups = grouped(markers.worldMarkers or {}, markers.stageMarkers)
	if #worldGroups > 0 then
		local worldChips: { [string]: any } = {
			Label = e(Controls.Text, { text = "World", tone = "dim", size = size.secondary, height = 26, autoWidth = true, layoutOrder = 1 }),
		}
		markerChips(worldGroups, "w", worldChips)
		children.WorldMarkers = e(Controls.Line, { wrap = true, gap = 6, layoutOrder = 102 }, worldChips)
	end
	if snapshot.listErrors.markers then
		children.MarkerError = e(Controls.Empty, { text = snapshot.listErrors.markers, bad = true, layoutOrder = 103 })
	end

	-- Spawn.
	local kind = spawnKind or kinds[1]
	local options: { [string]: any } = {}
	if tonumber(areaLevel) then
		options.areaLevel = tonumber(areaLevel)
	end
	if rank ~= "" then
		options.rank = rank
	end
	local optionsText = if next(options) then " " .. HttpService:JSONEncode(options) else ""
	local countOk = tonumber(spawnCount) ~= nil
	children.SpawnLabel = e(Controls.SectionLabel, {
		text = "Spawn · in front of you",
		layoutOrder = 200,
		right = {
			Despawn = e(Controls.Button, {
				text = "Despawn all",
				busy = snapshot.busy.despawn,
				onActivated = function()
					ConsoleStore.run("despawn all", { key = "despawn", refresh = { "npcs" } })
				end,
			}),
		},
	})
	children.Spawn = e(Controls.Line, { wrap = true, gap = 6, layoutOrder = 201 }, {
		Kind = e(Controls.Select, {
			value = kind,
			choices = kinds,
			placeholder = "kind",
			onPick = function(picked: string?)
				setSpawnKind(picked)
			end,
			width = 116,
			layoutOrder = 1,
		}),
		Count = e(Controls.Input, { text = spawnCount, width = 44, invalid = not countOk, onChange = setSpawnCount, layoutOrder = 2 }),
		LevelLabel = e(Controls.Text, { text = "level", tone = "secondary", size = size.secondary, height = 28, autoWidth = true, layoutOrder = 3 }),
		Level = e(Controls.Input, { text = areaLevel, placeholder = "–", width = 44, onChange = setAreaLevel, layoutOrder = 4 }),
		Rank = e(Controls.Input, { text = rank, placeholder = "rank", width = 76, onChange = setRank, layoutOrder = 5 }),
		Go = e(Controls.Button, {
			text = "Spawn",
			enabled = countOk and kind ~= nil,
			busy = kind ~= nil and snapshot.busy["spawn:" .. kind],
			layoutOrder = 6,
			onActivated = function()
				if kind then
					ConsoleStore.run(`spawn {kind} {spawnCount}{optionsText}`, { key = "spawn:" .. kind, refresh = { "npcs" } })
				end
			end,
		}),
	})
	if #kinds == 0 then
		children.SpawnEmpty = e(Controls.Empty, { text = "No NPC kinds (ReplicatedStorage.Assets.NPCPrefabs).", layoutOrder = 202 })
	end

	-- NPCs.
	children.NpcLabel = e(Controls.SectionLabel, { text = `NPCs · {#npcs}`, layoutOrder = 300 })
	for index, npc in ipairs(npcs) do
		local key = "npc:" .. npcTarget(npc)
		local hasHealth = npc.health ~= nil and npc.maxHealth ~= nil
		local ratio = if hasHealth and npc.maxHealth > 0 then npc.health / npc.maxHealth else 0
		children[`n{index}`] = e(Controls.Row, {
			title = npc.name,
			titleWidth = 96,
			titleTone = if npc.dead then "dim" else nil,
			dot = if npc.dead then "bad" else nil,
			selected = key == selectedKey,
			onSelect = function()
				ConsoleStore.pick(TAB, key)
			end,
			body = {
				Bar = e(Controls.Bar, { ratio = ratio, color = if npc.dead then color.dim else color.ok, layoutOrder = 1 }),
				Value = e(Controls.Text, {
					text = if npc.dead then "dying" elseif hasHealth then `{round(npc.health)}/{round(npc.maxHealth)}` else "–",
					mono = true,
					size = size.monoSmall,
					tone = if npc.dead then "bad" else "secondary",
					height = Theme.space.row,
					width = UDim.new(0, 72),
					alignX = Enum.TextXAlignment.Right,
					layoutOrder = 2,
				}),
			},
			layoutOrder = 300 + index,
		})
	end
	if #npcs == 0 then
		children.NpcEmpty = e(Controls.Empty, {
			text = snapshot.listErrors.npcs or "No NPCs in the world.",
			bad = snapshot.listErrors.npcs ~= nil,
			layoutOrder = 301,
		})
	end

	-- The detail pane.
	local detail: any = nil
	if selectedStage then
		local stage = selectedStage
		local label = stageLoad(stage)
		detail = e(Controls.DetailPane, {
			title = stage.name,
			id = "stage",
			description = "Loads the map only. Load the scenario of the same name for its spawns and character.",
			rows = {
				{ "State", if stage.current then "loaded" else "not loaded" },
				if stage.current then { "Markers", tostring(markerCount) } else nil,
			} :: any,
			actions = {
				Load = e(Controls.Button, {
					text = label,
					primary = true,
					kbd = true,
					busy = snapshot.busy["stage:" .. stage.name],
					enabled = not stageBusy,
					layoutOrder = 1,
					onActivated = function()
						local _, command = stageLoad(stage)
						ConsoleStore.run(command, { key = "stage:" .. stage.name, refresh = stageRefresh })
					end,
				}),
				Unload = e(Controls.Button, {
					text = "Unload",
					enabled = snapshot.devState.stageName ~= "" and not stageBusy,
					busy = snapshot.busy["stage:unload"],
					layoutOrder = 2,
					onActivated = function()
						ConsoleStore.run("stage unload", { key = "stage:unload", refresh = stageRefresh })
					end,
				}),
			},
		})
	elseif selectedNpc then
		local npc = selectedNpc
		local target = npcTarget(npc)
		local amountOk = tonumber(hitAmount) ~= nil
		local rows: { { any } } = {
			{ "Health", if npc.health and npc.maxHealth then `{round(npc.health)} / {round(npc.maxHealth)}` else "none", true },
		}
		if npc.kind ~= npc.name then
			table.insert(rows, { "Kind", npc.kind })
		end
		if npc.position then
			table.insert(rows, { "Position", `{npc.position[1]}, {npc.position[2]}, {npc.position[3]}`, true })
		end
		if npc.tag then
			table.insert(rows, { "Tag", npc.tag, true })
		end
		detail = e(Controls.DetailPane, {
			title = npc.name,
			id = tostring(npc.entityId or "?"),
			rows = rows,
			actions = {
				Hit = e(Controls.Button, {
					text = `Hit {hitAmount}`,
					primary = true,
					kbd = true,
					enabled = not npc.dead and amountOk,
					busy = snapshot.busy["hit:" .. target],
					layoutOrder = 1,
					onActivated = function()
						ConsoleStore.run(`hit {Controls.quote(target)} {hitAmount}`, { key = "hit:" .. target, refresh = { "npcs" } })
					end,
				}),
				Status = e(Controls.Button, {
					text = if effect then `Apply {effect}` else "Apply status",
					enabled = not npc.dead and effect ~= nil,
					busy = snapshot.busy["status:" .. target],
					layoutOrder = 2,
					onActivated = function()
						ConsoleStore.run(`status {Controls.quote(target)} {effect}`, { key = "status:" .. target, refresh = { "npcs" } })
					end,
				}),
				Inspect = e(Controls.Button, {
					text = "Inspect",
					layoutOrder = 3,
					onActivated = function()
						ConsoleStore.setInspectTarget(target)
						ConsoleStore.setTab("inspect")
					end,
				}),
				Despawn = e(Controls.Button, {
					text = `Despawn every {npc.kind}`,
					busy = snapshot.busy.despawn,
					layoutOrder = 4,
					onActivated = function()
						ConsoleStore.run(`despawn {Controls.quote(npc.kind)}`, { key = "despawn", refresh = { "npcs" } })
					end,
				}),
			},
		}, {
			Settings = e(Controls.Line, { inset = false, vertical = 0, gap = 6, wrap = true, layoutOrder = 1 }, {
				HitLabel = e(Controls.Text, { text = "Hit for", tone = "dim", size = size.secondary, height = 28, width = UDim.new(0, 100 - 6), layoutOrder = 1 }),
				Hit = e(Controls.Input, { text = hitAmount, width = 60, invalid = not amountOk, onChange = setHitAmount, layoutOrder = 2 }),
				EffectLabel = e(Controls.Text, { text = "status", tone = "dim", size = size.secondary, height = 28, autoWidth = true, layoutOrder = 3 }),
				Effect = e(Controls.Select, {
					value = effect,
					choices = ConsoleStore.choices("status", "effect"),
					placeholder = "effect",
					onPick = setEffect,
					width = 150,
					layoutOrder = 4,
				}),
			}),
		})
	end

	return e(Controls.TabLayout, { detail = detail }, children)
end

return WorldTab
