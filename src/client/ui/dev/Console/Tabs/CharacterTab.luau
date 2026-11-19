--!strict
-- Character: presets to put on, the way back to the real save, capturing the live build as a preset,
-- reading any preset's source, and quick changes to the live build (XP, mastery, items, pools).
--
-- The quick changes act on whichever save is in use, so while on the real save they sit under the
-- same red warning as the header.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local Console = script.Parent.Parent
local ThemeContext = require(Console.Parent.Parent.hooks.ThemeContext)
local ConsoleStore = require(Console.ConsoleStore)
local Controls = require(Console.Controls)

local e = React.createElement

local BUSY = "character:"
local NAME_PATTERN = "^[%w_%-]+$"

local function PresetRow(props: { preset: any, snapshot: ConsoleStore.State, layoutOrder: number })
	local theme = ThemeContext.useTheme()
	local preset = props.preset
	local busy = ConsoleStore.anyBusy(props.snapshot, BUSY)
	return e(Controls.Card, { layoutOrder = props.layoutOrder, current = preset.current }, {
		Row = e(Controls.Row, { layoutOrder = 1, gap = 8 }, {
			Name = e(Controls.Label, {
				text = preset.name,
				mono = true,
				size = 18,
				height = Controls.ROW,
				width = UDim.new(0, 0),
				fill = true,
				color = if preset.current then theme.color.accent else theme.color.textPrimary,
				layoutOrder = 1,
			}),
			Source = if preset.source == "session"
				then e(Controls.Chip, { text = "this session", color = theme.color.critical, layoutOrder = 2 })
				else nil,
			Current = if preset.current then e(Controls.Chip, { text = "on", color = theme.color.accent, layoutOrder = 3 }) else nil,
			Show = e(Controls.Button, {
				text = "Source",
				busy = props.snapshot.busy["show"],
				layoutOrder = 4,
				onActivated = function()
					ConsoleStore.run(`character show {preset.name}`, { key = "show" })
				end,
			}),
			Apply = e(Controls.Button, {
				text = if preset.current then "Re-apply" else "Apply",
				tone = "primary",
				busy = props.snapshot.busy[BUSY .. preset.name],
				enabled = not busy,
				layoutOrder = 5,
				onActivated = function()
					ConsoleStore.run(`character apply {preset.name}`, {
						key = BUSY .. preset.name,
						refresh = { "presets" },
					})
				end,
			}),
		}),
	})
end

local function CharacterTab(props: { snapshot: ConsoleStore.State })
	local theme = ThemeContext.useTheme()
	local snapshot = props.snapshot
	local list = snapshot.lists.presets
	local presets: { any } = if list and list.presets then list.presets else {}
	local sandboxed = snapshot.devCharacter ~= ""
	local busy = ConsoleStore.anyBusy(snapshot, BUSY)

	local saveName, setSaveName = React.useState("")
	local xp, setXp = React.useState("1000")
	local track, setTrack = React.useState(nil :: string?)
	local branch, setBranch = React.useState("trunk" :: string?)
	local masteryXp, setMasteryXp = React.useState("500")
	local item, setItem = React.useState(nil :: string?)
	local count, setCount = React.useState("1")
	local rarity, setRarity = React.useState(nil :: string?)
	local pool, setPool = React.useState("Health" :: string?)
	local poolDelta, setPoolDelta = React.useState("-50")
	local dropCount, setDropCount = React.useState("1")

	local children: { [string]: any } = {}

	local rows: { [string]: any } = {}
	for index, preset in ipairs(presets) do
		rows[`p{index}`] = e(PresetRow, { preset = preset, snapshot = snapshot, layoutOrder = index })
	end
	rows.Restore = e(Controls.Row, { layoutOrder = 1000 }, {
		Restore = e(Controls.Button, {
			text = "Restore real save",
			enabled = sandboxed and not busy,
			busy = snapshot.busy[BUSY .. "restore"],
			layoutOrder = 1,
			onActivated = function()
				ConsoleStore.run("character restore", { key = BUSY .. "restore", refresh = { "presets" } })
			end,
		}),
		Note = e(Controls.Label, {
			text = if sandboxed then "drops everything done on the preset" else "you are on your real save",
			size = Controls.SMALL,
			height = Controls.ROW,
			width = UDim.new(0, 0),
			fill = true,
			color = theme.color.textMuted,
			layoutOrder = 2,
		}),
	})
	if #presets == 0 then
		rows.Empty = e(Controls.Label, {
			text = snapshot.listErrors.presets or "Reading presets…",
			color = if snapshot.listErrors.presets then theme.color.danger else theme.color.textMuted,
			layoutOrder = 0,
		})
	end
	children.Presets = e(Controls.Section, { title = "Presets", layoutOrder = 1 }, rows)

	-- Capture.
	local saved = snapshot.results.save
	local validName = string.match(saveName, NAME_PATTERN) ~= nil
	children.Save = e(Controls.Section, { title = "Save current as", layoutOrder = 2 }, {
		Form = e(Controls.Row, { layoutOrder = 1 }, {
			Name = e(Controls.Field, {
				text = saveName,
				placeholder = "preset-name",
				mono = true,
				fill = true,
				invalid = saveName ~= "" and not validName,
				onChange = setSaveName,
				onSubmit = function(text: string)
					if string.match(text, NAME_PATTERN) then
						ConsoleStore.run(`character save {text}`, { key = "save", refresh = { "presets" } })
					end
				end,
				layoutOrder = 1,
			}),
			Save = e(Controls.Button, {
				text = "Save",
				tone = "primary",
				enabled = validName,
				busy = snapshot.busy.save,
				layoutOrder = 2,
				onActivated = function()
					ConsoleStore.run(`character save {saveName}`, { key = "save", refresh = { "presets" } })
				end,
			}),
		}),
		Rule = e(Controls.Label, {
			text = "Letters, digits, - and _. Kept for this session; paste the source into the repo to keep it.",
			size = Controls.SMALL,
			wrap = true,
			color = if saveName ~= "" and not validName then theme.color.danger else theme.color.textMuted,
			layoutOrder = 2,
		}),
		Failed = if saved and not saved.ok then e(Controls.ResultLine, { result = saved, layoutOrder = 3 }) else nil,
		Path = if saved and saved.ok and saved.data
			then e(Controls.Label, {
				text = `Paste into {saved.data.path}`,
				mono = true,
				size = Controls.MONO,
				wrap = true,
				color = theme.color.success,
				layoutOrder = 4,
			})
			else nil,
		Source = if saved and saved.ok and saved.data
			then e(Controls.CodeView, { text = saved.data.source, height = 240, layoutOrder = 5 })
			else nil,
		Dismiss = if saved
			then e(Controls.Row, { layoutOrder = 6 }, {
				Clear = e(Controls.Button, {
					text = "Hide",
					onActivated = function()
						ConsoleStore.clearResult("save")
					end,
				}),
			})
			else nil,
	})

	-- Read a preset's (or the live build's) source.
	local shown = snapshot.results.show
	children.Show = e(Controls.Section, {
		title = "Source",
		layoutOrder = 3,
		right = e(Controls.Button, {
			text = "Live build",
			busy = snapshot.busy.show,
			onActivated = function()
				ConsoleStore.run("character show", { key = "show" })
			end,
		}),
	}, {
		Hint = if not shown
			then e(Controls.Label, {
				text = "Pick Source on a preset, or Live build for what you are playing now.",
				size = Controls.SMALL,
				wrap = true,
				color = theme.color.textMuted,
				layoutOrder = 1,
			})
			else nil,
		Failed = if shown and not shown.ok then e(Controls.ResultLine, { result = shown, layoutOrder = 2 }) else nil,
		Name = if shown and shown.ok and shown.data
			then e(Controls.Label, { text = shown.data.name, mono = true, bold = true, layoutOrder = 3 })
			else nil,
		Code = if shown and shown.ok and shown.data
			then e(Controls.CodeView, { text = shown.data.source, height = 240, layoutOrder = 4 })
			else nil,
	})

	-- Quick adjusters for the live build.
	local adjustResult = snapshot.results.adjust
	local function adjust(text: string)
		ConsoleStore.run(text, { key = "adjust" })
	end
	local adjustBusy = snapshot.busy.adjust
	local tracks = ConsoleStore.choices("mastery", "track")
	local items = ConsoleStore.choices("give", "itemId")
	local rarities = ConsoleStore.choices("give", "rarity")
	local pools = ConsoleStore.choices("pool", "pool")

	children.Adjust = e(Controls.Section, { title = "Adjust live build", layoutOrder = 4 }, {
		Warning = if not sandboxed
			then e("Frame", {
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundColor3 = theme.color.danger,
				BackgroundTransparency = 0.12,
				BorderSizePixel = 0,
				LayoutOrder = 1,
			}, {
				Padding = Controls.padding(10, 5),
				Text = e(Controls.Label, {
					text = "⚠  REAL SAVE — XP, mastery, items and drops below are written to your real save.",
					bold = true,
					size = Controls.SMALL,
					wrap = true,
				}),
			})
			else nil,
		Xp = e(Controls.LabelledRow, { label = "XP", layoutOrder = 2 }, {
			Amount = e(Controls.Field, { text = xp, mono = true, width = 110, onChange = setXp, layoutOrder = 1 }),
			Add = e(Controls.Button, {
				text = "Add XP",
				enabled = tonumber(xp) ~= nil,
				busy = adjustBusy,
				layoutOrder = 2,
				onActivated = function()
					adjust(`xp {xp}`)
				end,
			}),
		}),
		Mastery = e(Controls.LabelledRow, { label = "Mastery", hint = "track, branch, XP", layoutOrder = 3 }, {
			Form = e(Controls.Stack, { gap = 4, layoutOrder = 1 }, {
				Track = e(Controls.Choice, {
					value = track,
					choices = tracks,
					placeholder = "track",
					onPick = setTrack,
					layoutOrder = 1,
				}),
				Rest = e(Controls.Row, { layoutOrder = 2, wrap = true }, {
					Branch = e(Controls.Choice, {
						value = branch,
						choices = ConsoleStore.choices("mastery", "branch"),
						onPick = setBranch,
						width = 110,
						layoutOrder = 1,
					}),
					Xp = e(Controls.Field, { text = masteryXp, mono = true, width = 90, onChange = setMasteryXp, layoutOrder = 2 }),
					Set = e(Controls.Button, {
						text = "Set",
						enabled = track ~= nil and branch ~= nil and tonumber(masteryXp) ~= nil,
						busy = adjustBusy,
						layoutOrder = 3,
						onActivated = function()
							adjust(`mastery {track} {branch} {masteryXp}`)
						end,
					}),
				}),
			}),
		}),
		Give = e(Controls.LabelledRow, { label = "Give item", hint = "item, count, rarity", layoutOrder = 4 }, {
			Form = e(Controls.Stack, { gap = 4, layoutOrder = 1 }, {
				Item = e(Controls.Choice, {
					value = item,
					choices = items,
					placeholder = `item ({#items})`,
					onPick = setItem,
					layoutOrder = 1,
				}),
				Rest = e(Controls.Row, { layoutOrder = 2, wrap = true }, {
					Count = e(Controls.Field, { text = count, mono = true, width = 60, onChange = setCount, layoutOrder = 1 }),
					Rarity = e(Controls.Choice, {
						value = rarity,
						choices = rarities,
						placeholder = "rarity",
						allowClear = true,
						onPick = setRarity,
						width = 130,
						layoutOrder = 2,
					}),
					Give = e(Controls.Button, {
						text = "Give",
						enabled = item ~= nil and tonumber(count) ~= nil,
						busy = adjustBusy,
						layoutOrder = 3,
						onActivated = function()
							adjust(`give {item} {count}{if rarity then " " .. rarity else ""}`)
						end,
					}),
				}),
			}),
		}),
		Pools = e(Controls.LabelledRow, { label = "Pools", layoutOrder = 5 }, {
			Form = e(Controls.Stack, { gap = 4, layoutOrder = 1 }, {
				Heal = e(Controls.Row, { layoutOrder = 1 }, {
					Heal = e(Controls.Button, {
						text = "Heal (refill all)",
						busy = adjustBusy,
						onActivated = function()
							adjust("heal")
						end,
					}),
				}),
				Delta = e(Controls.Row, { layoutOrder = 2, wrap = true }, {
					Pool = e(Controls.Choice, { value = pool, choices = pools, onPick = setPool, width = 130, layoutOrder = 1 }),
					Delta = e(Controls.Field, { text = poolDelta, mono = true, width = 80, onChange = setPoolDelta, layoutOrder = 2 }),
					Apply = e(Controls.Button, {
						text = "Change",
						enabled = pool ~= nil and tonumber(poolDelta) ~= nil,
						busy = adjustBusy,
						layoutOrder = 3,
						onActivated = function()
							adjust(`pool {pool} {poolDelta}`)
						end,
					}),
				}),
			}),
		}),
		Drop = e(Controls.LabelledRow, { label = "Drop", hint = "first bag items", layoutOrder = 6 }, {
			Count = e(Controls.Field, { text = dropCount, mono = true, width = 60, onChange = setDropCount, layoutOrder = 1 }),
			Drop = e(Controls.Button, {
				text = "Drop",
				enabled = tonumber(dropCount) ~= nil,
				busy = adjustBusy,
				layoutOrder = 2,
				onActivated = function()
					adjust(`drop {dropCount}`)
				end,
			}),
		}),
		Result = e(Controls.ResultLine, { result = adjustResult, layoutOrder = 7 }),
	})

	return e(Controls.Stack, { gap = 14 }, children)
end

return CharacterTab
