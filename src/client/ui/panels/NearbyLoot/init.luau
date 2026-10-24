--!strict
-- Nearby loot over gameplay (decision 4 in docs/tasks/ui-design-pass.md), in two states.
--
-- Collapsed (the default) each drop is only a marker -- its glyph in its rarity colour -- with the
-- rarest one in range marked out, and only the target E would take, the drop nearest the crosshair,
-- is named. A pile stays quiet during a fight.
--
-- Focused (precision focus held) the loot opens up to the cursor: up to the configured limit each drop
-- gets its label, past it the pile becomes one list over the nearest drop, and the selected drop's
-- details stand beside it. Hovering selects, clicking takes, the wheel steps.
--
-- All of it is screen UI placed at projected drop positions, like the vitals readout: one size at any
-- distance, drawn over effects. Labels that would overlap are stacked upward, nearer drops keeping
-- their natural spots. Selection and pickup go through LootClient for every path.
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
local LootClient = require(script.Parent.Parent.controllers.LootClient)
local LootDetails = require(script.LootDetails)
local LootList = require(script.LootList)
local LootMarker = require(script.LootMarker)
local LootPlate = require(script.LootPlate)

local e = React.createElement

local CONFIG = SharedConfig.WorldLootInspect

-- Until a plate has been laid out once and reported its size.
local DEFAULT_SIZE = Vector2.new(140, 28)

type Mode = "none" | "markers" | "labels" | "list"

-- Collapsed, every pile is markers. Focused, up to the limit a pile labels each drop; beyond it, the
-- list shows instead.
local function modeFor(count: number, focused: boolean): Mode
	if count == 0 then
		return "none"
	elseif not focused then
		return "markers"
	end
	return if count <= CONFIG.labels.limit then "labels" else "list"
end

-- Studs above a drop's centre for its marker.
local MARKER_HEIGHT = 0.6
-- Pixels between a label or the list and the details card beside it.
local CARD_GAP = 14

local RARITY_RANK: { [string]: number } = { normal = 1, magic = 2, rare = 3, unique = 4 }

-- Screen pixels kept clear around the list and the details card, and above the bottom of the screen,
-- where the skill bar sits.
local LIST_MARGIN = 16
local BOTTOM_CLEARANCE = 96

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
		math.clamp(top.Y, LIST_MARGIN + height, math.max(LIST_MARGIN + height, viewport.Y - BOTTOM_CLEARANCE))
	)
end

local function NearbyLoot()
	local snapshot = useNearbyLoot()
	local mode = modeFor(#snapshot.entries, snapshot.focused)

	local layout, setLayout = React.useBinding({} :: { [string]: LootPlate.Placement })
	local markers, setMarkers = React.useBinding({} :: { [string]: Vector2 })
	local listPosition, setListPosition = React.useBinding(UDim2.new())
	local cardPosition, setCardPosition = React.useBinding(UDim2.new())
	-- Read by the render-step loop, so they live in refs and the loop never restarts on a scan.
	local drops = React.useRef({} :: { Drop })
	local selected = React.useRef(nil :: string?)
	local sizes = React.useRef({} :: { [string]: Vector2 })

	local ordered = {}
	for _, entry in ipairs(snapshot.entries) do
		table.insert(ordered, { uid = entry.uid, part = entry.part })
	end
	drops.current = ordered
	selected.current = snapshot.selectedUid

	React.useEffect(function()
		if mode == "none" then
			return
		end
		local smoothed: { [string]: Vector2 } = {}
		local listAt: Vector2? = nil
		local cardAt: Vector2? = nil
		local name = `NearbyLoot_{HttpService:GenerateGUID(false)}`

		RunService:BindToRenderStep(name, Enum.RenderPriority.Camera.Value + 1, function(dt: number)
			local camera = workspace.CurrentCamera
			if not camera then
				return
			end
			local alpha = 1 - math.exp(-CONFIG.labels.followRate * dt)
			local current = drops.current :: { Drop }
			local sizeTable = sizes.current :: { [string]: Vector2 }

			if mode == "markers" then
				local out: { [string]: Vector2 } = {}
				local target: Drop? = nil
				for _, drop in ipairs(current) do
					if drop.part.Parent then
						local point = camera:WorldToViewportPoint(drop.part.Position + Vector3.new(0, MARKER_HEIGHT, 0))
						if point.Z > 0 then
							out[drop.uid] = Vector2.new(math.round(point.X), math.round(point.Y))
						end
					end
					if drop.uid == selected.current then
						target = drop
					end
				end
				setMarkers(out)
				-- Only the target is named, standing over its marker.
				setLayout(if target then placePlates(camera, { target }, sizeTable, smoothed, alpha) else {})
				return
			end

			local viewport = camera.ViewportSize
			local cardTarget: Vector2? = nil
			-- Where the card goes if it would run off the right: the other side of the label or list.
			local cardLeftX = 0
			if mode == "list" then
				local target = listTarget(camera, current[1], #current)
				if target then
					listAt = if listAt then listAt:Lerp(target, alpha) else target
					local at = listAt :: Vector2
					setListPosition(UDim2.fromOffset(math.round(at.X), math.round(at.Y)))
					cardTarget = Vector2.new(at.X + LootList.WIDTH / 2 + CARD_GAP, at.Y - LootList.height(#current))
					cardLeftX = at.X - LootList.WIDTH / 2 - CARD_GAP - LootDetails.SIZE.X
				end
			else
				-- Distance order only. Placing the selected plate first would rearrange the stack
				-- whenever the selection moved, sliding a different plate under the cursor, whose hover
				-- would then take the selection back.
				local placed = placePlates(camera, current, sizeTable, smoothed, alpha)
				setLayout(placed)
				-- Beside the whole stack rather than the selected label alone, so it never covers a label
				-- the cursor might want next; level with the selected one.
				local chosen = selected.current and placed[selected.current]
				if chosen then
					local right, left = -math.huge, math.huge
					for _, other in pairs(placed) do
						right = math.max(right, other.plate.X + other.size.X / 2)
						left = math.min(left, other.plate.X - other.size.X / 2)
					end
					cardTarget = Vector2.new(right + CARD_GAP, chosen.plate.Y - LootDetails.SIZE.Y / 2)
					cardLeftX = left - CARD_GAP - LootDetails.SIZE.X
				end
			end

			if cardTarget then
				-- Kept wholly on screen, and flipped to the left if it would run off the right.
				local card = cardTarget :: Vector2
				if card.X + LootDetails.SIZE.X > viewport.X - LIST_MARGIN then
					card = Vector2.new(cardLeftX, card.Y)
				end
				card = Vector2.new(
					math.clamp(card.X, LIST_MARGIN, math.max(LIST_MARGIN, viewport.X - LIST_MARGIN - LootDetails.SIZE.X)),
					math.clamp(card.Y, LIST_MARGIN, math.max(LIST_MARGIN, viewport.Y - BOTTOM_CLEARANCE - LootDetails.SIZE.Y))
				)
				cardAt = if cardAt then cardAt:Lerp(card, alpha) else card
				local at = cardAt :: Vector2
				setCardPosition(UDim2.fromOffset(math.round(at.X), math.round(at.Y)))
			end
		end)

		return function()
			RunService:UnbindFromRenderStep(name)
		end
	end, { mode })

	if mode == "none" then
		return nil
	end

	local view = Selector.buildView(snapshot)
	local children: { [string]: any } = {}

	local function plate(row: Selector.RowView): any
		return e(LootPlate, {
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

	if mode == "markers" then
		local rarest = 1
		for _, row in ipairs(view.rows) do
			rarest = math.max(rarest, RARITY_RANK[row.rarity] or 1)
		end
		for _, row in ipairs(view.rows) do
			children[`Marker{row.uid}`] = e(LootMarker, {
				row = row,
				rarest = rarest > 1 and (RARITY_RANK[row.rarity] or 1) == rarest,
				position = markers:map(function(all: { [string]: Vector2 })
					return all[row.uid]
				end),
			})
			if row.selected then
				children[`Plate{row.uid}`] = plate(row)
			end
		end
		return e(React.Fragment, nil, children)
	end

	if mode == "list" then
		children.List = e(LootList.render, {
			view = view,
			position = listPosition,
			onHovered = LootActions.select,
			onActivated = LootActions.pickup,
			onScrolled = LootActions.cycle,
		})
	else
		for _, row in ipairs(view.rows) do
			children[`Plate{row.uid}`] = plate(row)
		end
	end

	-- Focused: the selected drop's details beside it.
	local selectedEntry: LootClient.LootEntry? = nil
	for _, entry in ipairs(snapshot.entries) do
		if entry.uid == snapshot.selectedUid then
			selectedEntry = entry
		end
	end
	if selectedEntry then
		children.Details = e(LootDetails.render, {
			entry = selectedEntry,
			position = cardPosition,
		})
	end
	return e(React.Fragment, nil, children)
end

return NearbyLoot
