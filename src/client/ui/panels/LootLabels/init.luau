--!strict
-- Name plates over nearby drops (decision 4 in docs/tasks/ui-design-pass.md): each item labelled
-- where it lies while few enough are in range to read that way. Past the configured limit this draws
-- nothing and the list panel over the nearest drop takes over (PanelRegistry's loot entry).
--
-- Screen UI placed at each drop's projected position, like the vitals readout: plates keep one size
-- at any distance and draw over effects. Plates that would overlap are stacked upward, the nearest
-- (and the selected one, placed first) keeping its natural spot.
--
-- Selection, hover and pickup all go through LootClient, the same as the list panel, so the
-- keyboard's up/down and E agree with whichever plate the pointer last touched.
--
-- `script` here IS the LootLabels module (init.luau collapses into its folder), so Parent is `panels`
-- and Parent.Parent is `ui`.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local React = require(ReplicatedStorage.Packages.React)

local useNearbyLoot = require(script.Parent.Parent.hooks.useNearbyLoot)
local LootActions = require(script.Parent.Parent.actions.LootActions)
local Selector = require(script.Parent.Parent.selectors.lootList)
local SharedConfig = require(ReplicatedStorage.Shared.Config)
local LootPlate = require(script.LootPlate)

local e = React.createElement

local CONFIG = SharedConfig.WorldLootInspect

-- Until a plate has been laid out once and reported its size.
local DEFAULT_SIZE = Vector2.new(140, 28)

-- Up to here, a pile labels each drop; beyond it, the list panel shows instead.
local function showsLabels(count: number): boolean
	return count > 0 and count <= CONFIG.labels.limit
end

type Placed = { centre: Vector2, size: Vector2 }
-- `rank` is the drop's place in LootClient's nearest-first order.
type Drop = { uid: string, part: BasePart, rank: number }

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

local function LootLabels()
	local snapshot = useNearbyLoot()
	local show = showsLabels(#snapshot.entries)

	local layout, setLayout = React.useBinding({} :: { [string]: LootPlate.Placement })
	-- Read by the render-step loop, so they live in refs and the loop never restarts on a scan.
	local drops = React.useRef({} :: { Drop })
	local selected = React.useRef(nil :: string?)
	local sizes = React.useRef({} :: { [string]: Vector2 })

	local ordered = {}
	for rank, entry in ipairs(snapshot.entries) do
		table.insert(ordered, { uid = entry.uid, part = entry.part, rank = rank })
	end
	drops.current = ordered
	selected.current = snapshot.selectedUid

	React.useEffect(function()
		if not show then
			return
		end
		local tuning = CONFIG.labels
		local smoothed: { [string]: Vector2 } = {}
		local name = `LootLabels_{HttpService:GenerateGUID(false)}`

		RunService:BindToRenderStep(name, Enum.RenderPriority.Camera.Value + 1, function(dt: number)
			local camera = workspace.CurrentCamera
			if not camera then
				return
			end
			local alpha = 1 - math.exp(-tuning.followRate * dt)

			-- The selected plate is placed first so stacking never shoves it off its own drop; the rest
			-- keep distance order, which must be total or plates would swap places between frames.
			local order = table.clone(drops.current :: { Drop })
			table.sort(order, function(a: Drop, b: Drop)
				local aSelected, bSelected = a.uid == selected.current, b.uid == selected.current
				if aSelected ~= bSelected then
					return aSelected
				end
				return a.rank < b.rank
			end)

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

				local size = (sizes.current :: { [string]: Vector2 })[drop.uid] or DEFAULT_SIZE
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
			setLayout(out)
		end)

		return function()
			RunService:UnbindFromRenderStep(name)
		end
	end, { show })

	if not show then
		return nil
	end

	local view = Selector.buildView(snapshot)
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
		})
	end
	return e(React.Fragment, nil, plates)
end

return LootLabels
