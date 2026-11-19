--!strict
-- World: stages, markers and teleports, a spawn palette, and the NPCs in the world.
--
-- The NPC list is read again every second or so while this tab is showing, so health and deaths
-- follow what happens in front of the developer. Per-row actions address an NPC by its entity id,
-- which `hit` and `status` accept as well as a name, so the row acted on is the one clicked even
-- among several of the same kind.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local Console = script.Parent.Parent
local ThemeContext = require(Console.Parent.Parent.hooks.ThemeContext)
local ConsoleStore = require(Console.ConsoleStore)
local Controls = require(Console.Controls)

local e = React.createElement

local NPC_POLL_SECONDS = 1.2

local function MarkerRow(props: { name: string, scope: string, snapshot: ConsoleStore.State, layoutOrder: number })
	local theme = ThemeContext.useTheme()
	return e(Controls.Row, { layoutOrder = props.layoutOrder, height = Controls.ROW }, {
		Name = e(Controls.Label, {
			text = props.name,
			mono = true,
			size = Controls.MONO,
			height = Controls.ROW,
			width = UDim.new(0, 0),
			fill = true,
			layoutOrder = 1,
		}),
		Scope = e(Controls.Label, {
			text = props.scope,
			size = Controls.SMALL,
			height = Controls.ROW,
			autoWidth = true,
			color = theme.color.textMuted,
			layoutOrder = 2,
		}),
		Tp = e(Controls.Button, {
			text = "Teleport",
			busy = props.snapshot.busy["tp:" .. props.name],
			layoutOrder = 3,
			onActivated = function()
				ConsoleStore.run(`tp {Controls.quote(props.name)}`, { key = "tp:" .. props.name })
			end,
		}),
	})
end

local function NpcRow(props: {
	npc: any,
	snapshot: ConsoleStore.State,
	hitAmount: string,
	effect: string?,
	layoutOrder: number,
})
	local theme = ThemeContext.useTheme()
	local npc = props.npc
	local target = npc.entityId or npc.name
	local health = if npc.health and npc.maxHealth
		then `{math.floor(npc.health + 0.5)} / {math.floor(npc.maxHealth + 0.5)}`
		else "no health"
	local ratio = if npc.health and npc.maxHealth and npc.maxHealth > 0 then math.clamp(npc.health / npc.maxHealth, 0, 1) else 0
	local inspecting = props.snapshot.inspectTarget == target

	return e(Controls.Card, { layoutOrder = props.layoutOrder, current = inspecting }, {
		Top = e(Controls.Row, { layoutOrder = 1, gap = 8 }, {
			Name = e(Controls.Label, {
				text = npc.name,
				bold = true,
				height = 26,
				autoWidth = true,
				color = if npc.dead then theme.color.textMuted else theme.color.textPrimary,
				layoutOrder = 1,
			}),
			Kind = if npc.kind ~= npc.name
				then e(Controls.Label, {
					text = npc.kind,
					size = Controls.SMALL,
					height = 26,
					autoWidth = true,
					color = theme.color.textMuted,
					layoutOrder = 2,
				})
				else nil,
			Dead = if npc.dead then e(Controls.Chip, { text = "dying", color = theme.color.danger, layoutOrder = 3 }) else nil,
			Id = e(Controls.Label, {
				text = tostring(npc.entityId or "?"),
				mono = true,
				size = Controls.MONO,
				height = 26,
				width = UDim.new(0, 0),
				fill = true,
				alignX = Enum.TextXAlignment.Right,
				color = theme.color.textMuted,
				layoutOrder = 4,
			}),
		}),
		Health = e(Controls.Row, { layoutOrder = 2, gap = 8, height = 22 }, {
			Bar = e("Frame", {
				Size = UDim2.new(0, 0, 0, 8),
				BackgroundColor3 = theme.color.gaugeTrack,
				BorderSizePixel = 0,
				LayoutOrder = 1,
			}, {
				Flex = e("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill }),
				Stroke = e("UIStroke", { Color = theme.color.stroke, Transparency = 0.7, Thickness = 1 }),
				Fill = e("Frame", {
					Size = UDim2.fromScale(ratio, 1),
					BackgroundColor3 = theme.color.danger,
					BorderSizePixel = 0,
				}),
			}),
			Value = e(Controls.Label, {
				text = health,
				mono = true,
				size = Controls.MONO,
				height = 22,
				width = UDim.new(0, 120),
				alignX = Enum.TextXAlignment.Right,
				layoutOrder = 2,
			}),
		}),
		Meta = e(Controls.Label, {
			text = `at {npc.position[1]}, {npc.position[2]}, {npc.position[3]}{if npc.tag then "  ·  tag " .. npc.tag else ""}`,
			size = Controls.SMALL,
			color = theme.color.textMuted,
			layoutOrder = 3,
		}),
		Actions = e(Controls.Row, { layoutOrder = 4, wrap = true }, {
			Hit = e(Controls.Button, {
				text = `Hit {props.hitAmount}`,
				enabled = not npc.dead and tonumber(props.hitAmount) ~= nil,
				busy = props.snapshot.busy["hit:" .. target],
				layoutOrder = 1,
				onActivated = function()
					ConsoleStore.run(`hit {Controls.quote(target)} {props.hitAmount}`, {
						key = "hit:" .. target,
						refresh = { "npcs" },
					})
				end,
			}),
			Status = e(Controls.Button, {
				text = if props.effect then `Apply {props.effect}` else "Apply status",
				enabled = not npc.dead and props.effect ~= nil,
				busy = props.snapshot.busy["status:" .. target],
				layoutOrder = 2,
				onActivated = function()
					ConsoleStore.run(`status {Controls.quote(target)} {props.effect}`, {
						key = "status:" .. target,
						refresh = { "npcs" },
					})
				end,
			}),
			Inspect = e(Controls.Button, {
				text = "Inspect",
				selected = inspecting,
				layoutOrder = 3,
				onActivated = function()
					ConsoleStore.setInspectTarget(target)
					ConsoleStore.setTab("inspect")
				end,
			}),
		}),
	})
end

local function WorldTab(props: { snapshot: ConsoleStore.State, active: boolean })
	local theme = ThemeContext.useTheme()
	local snapshot = props.snapshot
	local stagesData = snapshot.lists.stages
	local stages: { any } = if stagesData and stagesData.stages then stagesData.stages else {}
	local markers = snapshot.lists.markers or {}
	local npcData = snapshot.lists.npcs
	local npcs: { any } = if npcData and npcData.npcs then npcData.npcs else {}

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

	local children: { [string]: any } = {}

	-- Stages.
	local stageRows: { [string]: any } = {}
	for index, stage in ipairs(stages) do
		stageRows[`s{index}`] = e(Controls.Row, { layoutOrder = index, height = Controls.ROW }, {
			Name = e(Controls.Label, {
				text = stage.name,
				mono = true,
				size = Controls.MONO,
				height = Controls.ROW,
				width = UDim.new(0, 0),
				fill = true,
				color = if stage.current then theme.color.accent else theme.color.textPrimary,
				layoutOrder = 1,
			}),
			Current = if stage.current then e(Controls.Chip, { text = "loaded", color = theme.color.accent, layoutOrder = 2 }) else nil,
			Load = e(Controls.Button, {
				text = if stage.current then "Reload map" else "Load map",
				busy = snapshot.busy["stage:" .. stage.name],
				enabled = not ConsoleStore.anyBusy(snapshot, "stage:"),
				layoutOrder = 3,
				onActivated = function()
					ConsoleStore.run(`stage load {Controls.quote(stage.name)}`, {
						key = "stage:" .. stage.name,
						refresh = { "stages", "markers", "scenarios" },
					})
				end,
			}),
		})
	end
	if #stages == 0 then
		stageRows.Empty = e(Controls.Label, {
			text = snapshot.listErrors.stages or "No stages in ServerStorage.Scenarios.",
			size = Controls.SMALL,
			color = theme.color.textMuted,
			layoutOrder = 0,
		})
	end
	stageRows.Note = e(Controls.Label, {
		text = "Loads the map only. Load the scenario of the same name for its spawns and character.",
		size = Controls.SMALL,
		wrap = true,
		color = theme.color.textMuted,
		layoutOrder = 999,
	})
	children.Stages = e(Controls.Section, {
		title = "Stages",
		layoutOrder = 1,
		right = e(Controls.Button, {
			text = "Unload",
			enabled = snapshot.devState.stageName ~= "" and not ConsoleStore.anyBusy(snapshot, "stage:"),
			busy = snapshot.busy["stage:unload"],
			onActivated = function()
				ConsoleStore.run("stage unload", { key = "stage:unload", refresh = { "stages", "markers", "scenarios" } })
			end,
		}),
	}, stageRows)

	-- Markers.
	local markerRows: { [string]: any } = {}
	local order = 0
	for _, name in ipairs(markers.stageMarkers or {}) do
		order += 1
		markerRows[`m{order}`] = e(MarkerRow, { name = name, scope = "stage", snapshot = snapshot, layoutOrder = order })
	end
	for _, name in ipairs(markers.worldMarkers or {}) do
		if not table.find(markers.stageMarkers or {}, name) then
			order += 1
			markerRows[`m{order}`] = e(MarkerRow, { name = name, scope = "world", snapshot = snapshot, layoutOrder = order })
		end
	end
	if order == 0 then
		markerRows.Empty = e(Controls.Label, {
			text = snapshot.listErrors.markers or "No markers on the stage or in the world.",
			size = Controls.SMALL,
			color = theme.color.textMuted,
			layoutOrder = 0,
		})
	end
	children.Markers = e(Controls.Section, {
		title = "Markers",
		layoutOrder = 2,
		right = e(Controls.Button, {
			text = "Teleport to start",
			busy = snapshot.busy["tp:start"],
			onActivated = function()
				ConsoleStore.run("tp start", { key = "tp:start" })
			end,
		}),
	}, {
		Show = e(Controls.Row, { layoutOrder = 0, height = Controls.ROW }, {
			Toggle = e(Controls.Toggle, {
				value = markers.visible == true,
				busy = snapshot.busy.markers,
				layoutOrder = 1,
				onToggle = function()
					ConsoleStore.run(if markers.visible then "markers hide" else "markers show", {
						key = "markers",
						refresh = { "markers" },
					})
				end,
			}),
			Label = e(Controls.Label, {
				text = "Show markers in the world",
				height = Controls.ROW,
				autoWidth = true,
				layoutOrder = 2,
			}),
		}),
		List = e(Controls.Stack, { gap = 2, layoutOrder = 1 }, markerRows),
	})

	-- Spawn palette.
	local kinds = ConsoleStore.choices("spawn", "kind")
	local options: { [string]: any } = {}
	if tonumber(areaLevel) then
		options.areaLevel = tonumber(areaLevel)
	end
	if rank ~= "" then
		options.rank = rank
	end
	local optionsText = if next(options) then " " .. HttpService:JSONEncode(options) else ""
	local countOk = tonumber(spawnCount) ~= nil
	local palette: { [string]: any } = {}
	for index, kind in ipairs(kinds) do
		palette[`k{index}`] = e(Controls.Button, {
			text = kind,
			tone = "primary",
			enabled = countOk,
			busy = snapshot.busy["spawn:" .. kind],
			layoutOrder = index,
			onActivated = function()
				ConsoleStore.run(`spawn {kind} {spawnCount}{optionsText}`, { key = "spawn:" .. kind, refresh = { "npcs" } })
			end,
		})
	end
	children.Spawn = e(Controls.Section, {
		title = "Spawn",
		layoutOrder = 3,
		right = e(Controls.Button, {
			text = "Despawn all",
			tone = "danger",
			busy = snapshot.busy.despawn,
			onActivated = function()
				ConsoleStore.run("despawn all", { key = "despawn", refresh = { "npcs" } })
			end,
		}),
	}, {
		Options = e(Controls.Row, { layoutOrder = 1, wrap = true }, {
			CountLabel = e(Controls.Label, { text = "Count", bold = true, height = Controls.ROW, autoWidth = true, layoutOrder = 1 }),
			Count = e(Controls.Field, { text = spawnCount, mono = true, width = 56, onChange = setSpawnCount, invalid = not countOk, layoutOrder = 2 }),
			LevelLabel = e(Controls.Label, { text = "Area level", bold = true, height = Controls.ROW, autoWidth = true, layoutOrder = 3 }),
			Level = e(Controls.Field, { text = areaLevel, placeholder = "—", mono = true, width = 56, onChange = setAreaLevel, layoutOrder = 4 }),
			RankLabel = e(Controls.Label, { text = "Rank", bold = true, height = Controls.ROW, autoWidth = true, layoutOrder = 5 }),
			Rank = e(Controls.Field, { text = rank, placeholder = "—", mono = true, width = 90, onChange = setRank, layoutOrder = 6 }),
		}),
		Palette = e(Controls.Row, { layoutOrder = 2, wrap = true }, palette),
		Empty = if #kinds == 0
			then e(Controls.Label, { text = "No NPC kinds (ReplicatedStorage.Assets.NPCPrefabs).", size = Controls.SMALL, color = theme.color.textMuted, layoutOrder = 3 })
			else nil,
		Note = e(Controls.Label, {
			text = "Spawns in front of you, on the ground.",
			size = Controls.SMALL,
			color = theme.color.textMuted,
			layoutOrder = 4,
		}),
	})

	-- NPCs.
	local npcRows: { [string]: any } = {}
	for index, npc in ipairs(npcs) do
		npcRows[`n{index}`] = e(NpcRow, {
			npc = npc,
			snapshot = snapshot,
			hitAmount = hitAmount,
			effect = effect,
			layoutOrder = index,
		})
	end
	if #npcs == 0 then
		npcRows.Empty = e(Controls.Label, {
			text = snapshot.listErrors.npcs or "No NPCs in the world.",
			size = Controls.SMALL,
			color = theme.color.textMuted,
			layoutOrder = 0,
		})
	end
	children.Npcs = e(Controls.Section, { title = `NPCs  ({#npcs})`, layoutOrder = 4 }, {
		Settings = e(Controls.Row, { layoutOrder = 0, wrap = true, alignY = Enum.VerticalAlignment.Top }, {
			HitLabel = e(Controls.Label, { text = "Hit for", bold = true, height = Controls.ROW, autoWidth = true, layoutOrder = 1 }),
			Hit = e(Controls.Field, { text = hitAmount, mono = true, width = 70, onChange = setHitAmount, invalid = tonumber(hitAmount) == nil, layoutOrder = 2 }),
			EffectLabel = e(Controls.Label, { text = "Status", bold = true, height = Controls.ROW, autoWidth = true, layoutOrder = 3 }),
			Effect = e(Controls.Choice, {
				value = effect,
				choices = ConsoleStore.choices("status", "effect"),
				placeholder = "effect",
				onPick = setEffect,
				width = 190,
				layoutOrder = 4,
			}),
		}),
		List = e(Controls.Stack, { gap = 6, layoutOrder = 1 }, npcRows),
	})

	return e(Controls.Stack, { gap = 14 }, children)
end

return WorldTab
