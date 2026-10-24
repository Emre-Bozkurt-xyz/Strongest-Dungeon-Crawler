--!strict
-- Nearby loot over gameplay (decision 4 in docs/tasks/ui-design-pass.md). Up to the configured limit
-- each drop gets a name plate where it lies; past it, the pile collapses into one list standing over
-- the nearest drop, so a late-game heap reads at a glance.
--
-- Both are screen UI placed at projected drop positions, like the vitals readout: they keep one size
-- at any distance and draw over effects. Plates that would overlap are stacked upward, nearer drops
-- keeping their natural spots.
--
-- Selection, hover, the wheel and pickup all go through LootClient, so E always takes whichever
-- plate or row the pointer last touched or the wheel last moved to.
--
-- `script` here IS the NearbyLoot module (init.luau collapses into its folder), so Parent is `panels`
-- and Parent.Parent is `ui`.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local React = require(ReplicatedStorage.Packages.React)

local useNearbyLoot = require(script.Parent.Parent.hooks.useNearbyLoot)
local LootActions = require(script.Parent.Parent.actions.LootActions)
local Selector = require(script.Parent.Parent.selectors.lootList)
local SharedConfig = require(ReplicatedStorage.Shared.Config)
local LootList = require(script.LootList)
local LootPlate = require(script.LootPlate)

local e = React.createElement

local CONFIG = SharedConfig.WorldLootInspect

-- Until a plate has been laid out once and reported its size.
local DEFAULT_SIZE = Vector2.new(140, 28)

type Mode = "none" | "labels" | "list"

-- Up to the limit a pile labels each drop; beyond it, the list shows instead.
local function modeFor(count: number): Mode
	if count == 0 then
		return "none"
	end
	return if count <= CONFIG.labels.limit then "labels" else "list"
end

-- Screen pixels kept clear around the list.
local LIST_MARGIN = 16

type Placed = { centre: Vector2, size: Vector2 }
type Drop = { uid: string, part: BasePart }

local function overlaps(centre: Vector2, size: Vector2, other: Placed, gap: number): boolean
	return math.abs(centre.X - other.centre.X) < (size.X + other.size.X) / 2 + gap
		and math.abs(centre.Y - other.centre.Y) < (size.Y + other.size.Y) / 2 + gap
end

-- Moves a plate up past every placed plate it would overlap. Repeats, since clearing one can land it
-- on another higher up; a pile of `limit` plates settles well within the cap.
local function stackAbove(centre: Vector2, size: Vector2, placed: { Placed }, gap: number): Vector2
	for _ = 1, #placed + 1 do
		local moved = false
		for _, other in ipairs(placed) do
			if overlaps(centre, size, other, gap) then
				centre = Vector2.new(centre.X, other.centre.Y - (size.Y + other.size.Y) / 2 - gap)
				moved = true
			end
		end
		if not moved then
			break
		end
	end
	return centre
end


-- Plate placements for this frame: each drop's plate above it, stacked clear of the ones placed
-- before it.
local function placePlates(
	camera: Camera,
	order: { Drop },
	sizes: { [string]: Vector2 },
	smoothed: { [string]: Vector2 },
	alpha: number
): { [string]: LootPlate.Placement }
	local tuning = CONFIG.labels
	local placed: { Placed } = {}
	local out: { [string]: LootPlate.Placement } = {}
	for _, drop in ipairs(order) do
		local part = drop.part
		if not part.Parent then
			continue
		end
		local top = camera:WorldToViewportPoint(part.Position + Vector3.new(0, tuning.height, 0))
		local base = camera:WorldToViewportPoint(part.Position)
		if top.Z <= 0 or base.Z <= 0 then
			smoothed[drop.uid] = nil
			continue
		end

		local size = sizes[drop.uid] or DEFAULT_SIZE
		local target = stackAbove(Vector2.new(top.X, top.Y - size.Y / 2), size, placed, tuning.gap)
		table.insert(placed, { centre = target, size = size })

		local previous = smoothed[drop.uid]
		local centre = if previous then previous:Lerp(target, alpha) else target
		smoothed[drop.uid] = centre
		out[drop.uid] = {
			plate = Vector2.new(math.round(centre.X), math.round(centre.Y)),
			anchor = Vector2.new(math.round(base.X), math.round(base.Y)),
			size = size,
			visible = true,
		}
	end
	return out
end

-- Where the list's bottom centre wants to be: above the nearest drop, kept wholly on screen.
local function listTarget(camera: Camera, nearest: Drop?, rows: number): Vector2?
	if not nearest or not nearest.part.Parent then
		return nil
	end
	local top = camera:WorldToViewportPoint(nearest.part.Position + Vector3.new(0, CONFIG.labels.height, 0))
	if top.Z <= 0 then
		return nil
	end
	local viewport = camera.ViewportSize
	local halfWidth = LootList.WIDTH / 2
	local height = LootList.height(rows)
	return Vector2.new(
		math.clamp(top.X, LIST_MARGIN + halfWidth, math.max(LIST_MARGIN + halfWidth, viewport.X - LIST_MARGIN - halfWidth)),
		math.clamp(top.Y, LIST_MARGIN + height, math.max(LIST_MARGIN + height, viewport.Y - LIST_MARGIN))
	)
end

local function NearbyLoot()
	local snapshot = useNearbyLoot()
	local mode = modeFor(#snapshot.entries)

	local layout, setLayout = React.useBinding({} :: { [string]: LootPlate.Placement })
	local listPosition, setListPosition = React.useBinding(UDim2.new())
	-- Read by the render-step loop, so they live in refs and the loop never restarts on a scan.
	local drops = React.useRef({} :: { Drop })
	local sizes = React.useRef({} :: { [string]: Vector2 })

	local ordered = {}
	for _, entry in ipairs(snapshot.entries) do
		table.insert(ordered, { uid = entry.uid, part = entry.part })
	end
	drops.current = ordered

	React.useEffect(function()
		if mode == "none" then
			return
		end
		local smoothed: { [string]: Vector2 } = {}
		local listAt: Vector2? = nil
		local name = `NearbyLoot_{HttpService:GenerateGUID(false)}`

		RunService:BindToRenderStep(name, Enum.RenderPriority.Camera.Value + 1, function(dt: number)
			local camera = workspace.CurrentCamera
			if not camera then
				return
			end
			local alpha = 1 - math.exp(-CONFIG.labels.followRate * dt)
			local current = drops.current :: { Drop }

			if mode == "list" then
				local target = listTarget(camera, current[1], #current)
				if target then
					listAt = if listAt then listAt:Lerp(target, alpha) else target
					local at = listAt :: Vector2
					setListPosition(UDim2.fromOffset(math.round(at.X), math.round(at.Y)))
				end
				return
			end

			-- Distance order only. Placing the selected plate first would rearrange the stack whenever
			-- the wheel moved the selection, sliding a different plate under the cursor, whose hover
			-- would then take the selection back.
			setLayout(placePlates(camera, current, sizes.current :: { [string]: Vector2 }, smoothed, alpha))
		end)

		return function()
			RunService:UnbindFromRenderStep(name)
		end
	end, { mode })

	if mode == "none" then
		return nil
	end

	local view = Selector.buildView(snapshot)
	if mode == "list" then
		return e(LootList.render, {
			view = view,
			position = listPosition,
			onHovered = LootActions.select,
			onActivated = LootActions.pickup,
			onScrolled = LootActions.cycle,
		})
	end

	local plates: { [string]: any } = {}
	for _, row in ipairs(view.rows) do
		plates[row.uid] = e(LootPlate, {
			row = row,
			pickupKey = view.pickupKey,
			placement = layout:map(function(all: { [string]: LootPlate.Placement })
				return all[row.uid]
			end),
			onSize = function(uid: string, size: Vector2)
				(sizes.current :: { [string]: Vector2 })[uid] = size
			end,
			onHovered = LootActions.select,
			onActivated = LootActions.pickup,
			onScrolled = LootActions.cycle,
		})
	end
	return e(React.Fragment, nil, plates)
end

return NearbyLoot
