--!strict
-- LootClient: tracks nearby loot and the selected row, and handles pickup.
--
-- The store behind the nearby-loot plates and list (panels/NearbyLoot; R4 in
-- docs/tasks/ui-migration-plan.md). It owns the scan, the selection and the pickup key; the UI reads
-- a snapshot through useNearbyLoot and reports pointer input back through LootActions.
--
-- Loot has two states. Collapsed (the default) the drops are only marked, and the target is the drop
-- nearest the crosshair, which E takes. Focused (precision focus held) the drops open into labels the
-- cursor can work: hovering selects, clicking takes, the wheel steps, and the selection is whatever the
-- pointer last chose.
--
-- E is the only key it claims. Cycling the selection is the mouse wheel over the loot UI, not a key:
-- loot is nearby during fights, and a key that changes meaning whenever a drop is in range would
-- fight movement (the arrow keys did) and use up binds the game cannot spare.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local InteractionStateController = require(script.Parent.Parent.Parent.input.InteractionStateController)
local MenuOrchestrator = require(script.Parent.Parent.menu.MenuOrchestrator)
local ItemActions = require(script.Parent.Parent.actions.ItemActions)
local NotificationClient = require(script.Parent.NotificationClient)
local UISound = require(script.Parent.Parent.UISound)
local ItemGlyphs = require(script.Parent.Parent.glyphs.ItemGlyphs)
local Registry = require(ReplicatedStorage.Shared.items.Registry)
local SharedConfig = require(ReplicatedStorage.Shared.Config)
local ItemTypes = require(ReplicatedStorage.Shared.items.ItemTypes)

local LootClient = {}

export type LootEntry = {
	uid: string,
	itemId: string,
	displayName: string,
	rarity: string?,
	stackSize: number?,
	-- The instance meta (affixes, rolls), for showing the drop's details before it is taken.
	meta: ItemTypes.ItemMeta?,
	part: BasePart,
	distance: number,
}

export type Snapshot = {
	-- Nearest first. Empty while the menu is open, so the panel hides with no rule of its own.
	entries: { LootEntry },
	-- Precision focus is held: the loot is open to the cursor.
	focused: boolean,
	selectedUid: string?,
}

type TrackedDrop = {
	part: BasePart,
	prompt: ProximityPrompt?,
}

local CONFIG = SharedConfig.WorldLootInspect
local PICKUP_COOLDOWN = 0.15
local player = Players.LocalPlayer

local trackedDrops: { [BasePart]: TrackedDrop } = {}
local nearbyEntries = {} :: { LootEntry }
local selectedUid = nil :: string?
local snapshot: Snapshot = { entries = {}, selectedUid = nil, focused = false }
local snapshotSignature = ""
local listeners: { [{}]: () -> () } = {}
local scanAccumulator = 0
local menuOpen = false
local nextPickupAt = 0
local initialized = false

-- Decoded once per drop; the attribute does not change while it lies there.
local metaCache: { [string]: ItemTypes.ItemMeta | false } = {}

local function readMeta(part: BasePart, uid: string): ItemTypes.ItemMeta?
	local cached = metaCache[uid]
	if cached ~= nil then
		return if cached then cached else nil
	end
	local raw = part:GetAttribute("ItemMeta")
	local decoded: ItemTypes.ItemMeta | false = false
	if type(raw) == "string" then
		local ok, value = pcall(HttpService.JSONDecode, HttpService, raw)
		if ok and type(value) == "table" then
			decoded = value
		end
	end
	metaCache[uid] = decoded
	return if decoded then decoded else nil
end

local RARITY_RANK = {
	normal = 1,
	magic = 2,
	rare = 3,
	unique = 4,
}

local function getPlayerRoot(): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function readStringAttribute(part: BasePart, attributeName: string): string?
	local value = part:GetAttribute(attributeName)
	if type(value) == "string" and value ~= "" then
		return value
	end
	return nil
end

local function readNumberAttribute(part: BasePart, attributeName: string): number?
	local value = part:GetAttribute(attributeName)
	return if type(value) == "number" then value else nil
end

local function getDropEntry(part: BasePart, root: BasePart): LootEntry?
	local uid = readStringAttribute(part, "ItemUid")
	local itemId = readStringAttribute(part, "ItemId")
	if not uid or not itemId then
		return nil
	end

	local distance = (root.Position - part.Position).Magnitude
	if distance > CONFIG.maxDistance then
		return nil
	end

	return {
		uid = uid,
		itemId = itemId,
		displayName = readStringAttribute(part, "ItemDisplayName") or readStringAttribute(part, "ItemName") or itemId,
		rarity = readStringAttribute(part, "ItemRarity"),
		stackSize = readNumberAttribute(part, "ItemStackSize"),
		meta = readMeta(part, uid),
		part = part,
		distance = distance,
	}
end

local function sortEntries(entries: { LootEntry })
	table.sort(entries, function(a: LootEntry, b: LootEntry)
		if math.abs(a.distance - b.distance) > 0.05 then
			return a.distance < b.distance
		end
		local aRarity = RARITY_RANK[a.rarity or "normal"] or 0
		local bRarity = RARITY_RANK[b.rarity or "normal"] or 0
		if aRarity ~= bRarity then
			return aRarity > bRarity
		end
		if a.displayName ~= b.displayName then
			return a.displayName < b.displayName
		end
		return a.uid < b.uid
	end)
end

-- The panel replaces the per-drop prompts, so they stay off while LootClient tracks a drop. A drop's
-- prompt can be created after its tag lands, so this is re-applied on every scan rather than once.
local function suppressPrompt(tracked: TrackedDrop)
	local prompt = tracked.prompt or tracked.part:FindFirstChildWhichIsA("ProximityPrompt", true)
	tracked.prompt = prompt
	if prompt and prompt.Enabled then
		prompt.Enabled = false
	end
end

local function indexOf(uid: string?): number?
	if not uid then
		return nil
	end
	for index, entry in ipairs(nearbyEntries) do
		if entry.uid == uid then
			return index
		end
	end
	return nil
end

-- Only what the panel draws. Distances change on every scan as the player moves, so including them
-- would re-render the panel at the scan rate while showing exactly the same rows.
local function signatureOf(entries: { LootEntry }, selected: string?, focused: boolean): string
	local parts = table.create(#entries + 2)
	for _, entry in ipairs(entries) do
		table.insert(parts, `{entry.uid}:{entry.displayName}:{entry.rarity or ""}:{entry.stackSize or 1}`)
	end
	table.insert(parts, selected or "")
	table.insert(parts, tostring(focused))
	return table.concat(parts, "\n")
end

local function isFocused(): boolean
	return InteractionStateController.allowsWorldPanelInteraction()
end

local function publish()
	local focused = isFocused()
	local signature = signatureOf(nearbyEntries, selectedUid, focused)
	if signature == snapshotSignature then
		return
	end
	snapshotSignature = signature
	snapshot = { entries = table.clone(nearbyEntries), selectedUid = selectedUid, focused = focused }

	-- No payload: subscribers re-read through getSnapshot, the same contract every store hook
	-- follows (see "Never trust the payload" in the migration plan).
	for _, listener in pairs(listeners) do
		local ok, err = pcall(listener)
		if not ok then
			warn(`[LootClient] listener failed: {err}`)
		end
	end
end

local function targetUnderCrosshair(entries: { LootEntry }): string?
	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end
	local centre = camera.ViewportSize / 2
	local best: string? = nil
	local bestDistance = math.huge
	for _, entry in ipairs(entries) do
		local point = camera:WorldToViewportPoint(entry.part.Position)
		if point.Z > 0 then
			local offset = (Vector2.new(point.X, point.Y) - centre).Magnitude
			if offset < bestDistance then
				best = entry.uid
				bestDistance = offset
			end
		end
	end
	return best
end

local function refreshNearbyLoot()
	local entries: { LootEntry } = {}
	local root = getPlayerRoot()
	local hidden = CONFIG.hideWhenMenuOpen and menuOpen

	for part, tracked in pairs(trackedDrops) do
		if not part.Parent then
			trackedDrops[part] = nil
			continue
		end
		suppressPrompt(tracked)
		if root and not hidden then
			local entry = getDropEntry(part, root)
			if entry then
				table.insert(entries, entry)
			end
		end
	end

	sortEntries(entries)
	nearbyEntries = entries

	if not isFocused() then
		-- Collapsed, the target is what the player is looking at: the drop nearest the screen's
		-- centre, or the nearest one if none is on screen.
		selectedUid = targetUnderCrosshair(entries) or (if entries[1] then entries[1].uid else nil)
	elseif not indexOf(selectedUid) then
		-- Focused, selection follows the item, not the row: a drop that moves up the list as the
		-- player walks stays selected. Only when it leaves range does it fall back to the nearest.
		selectedUid = if entries[1] then entries[1].uid else nil
	end

	publish()
end

local function selectUid(uid: string)
	if not indexOf(uid) or selectedUid == uid then
		return
	end
	selectedUid = uid
	publish()
end

-- What the player is told when a pickup fails. Reasons not listed (the drop already gone, out of
-- reach by the time the request landed) pass silently: there is nothing for the player to act on.
local PICKUP_FAILURES: { [string]: { tag: string, text: string, tone: NotificationClient.Tone } } = {
	inventory_full = { tag = "INVENTORY FULL", text = "Make room to pick this up", tone = "error" },
	drop_claimed = { tag = "CLAIMED", text = "This drop belongs to another player", tone = "warning" },
}

local function pickupUid(uid: string)
	local index = indexOf(uid)
	if os.clock() < nextPickupAt or not index then
		return
	end
	nextPickupAt = os.clock() + PICKUP_COOLDOWN
	local entry = nearbyEntries[index :: number]

	-- The request yields for the server; this can be reached from a React event handler, which must
	-- not yield.
	task.spawn(function()
		local response = ItemActions.pickup(uid)
		if not response then
			return
		end
		if response.ok then
			NotificationClient.push({
				tag = "ITEM ACQUIRED",
				text = entry.displayName,
				rarity = entry.rarity or "normal",
				glyph = ItemGlyphs.forDef(Registry.get(entry.itemId)),
				count = entry.stackSize or 1,
				-- Merges repeat pickups of the same thing into one notice counting up.
				key = `pickup:{entry.itemId}:{entry.displayName}`,
			})
			return
		end
		local failure = response.error and PICKUP_FAILURES[response.error]
		if failure then
			NotificationClient.push({
				tag = failure.tag,
				text = failure.text,
				tone = failure.tone,
				key = `pickup-failed:{response.error}`,
			})
		end
	end)
end

local function changeSelection(direction: number)
	local count = #nearbyEntries
	if count == 0 then
		return
	end

	local nextIndex = (indexOf(selectedUid) or 1) + direction
	if CONFIG.selectionWrap then
		if nextIndex < 1 then
			nextIndex = count
		elseif nextIndex > count then
			nextIndex = 1
		end
	else
		nextIndex = math.clamp(nextIndex, 1, count)
	end

	selectUid(nearbyEntries[nextIndex].uid)
end

local function connectDrop(inst: Instance)
	if not inst:IsA("BasePart") then
		return
	end
	local tracked: TrackedDrop = { part = inst, prompt = nil }
	trackedDrops[inst] = tracked
	suppressPrompt(tracked)
end

local function disconnectDrop(inst: Instance)
	if not inst:IsA("BasePart") then
		return
	end
	local uid = inst:GetAttribute("ItemUid")
	if type(uid) == "string" then
		metaCache[uid] = nil
	end
	local tracked = trackedDrops[inst]
	if tracked and tracked.prompt then
		tracked.prompt.Enabled = true
	end
	trackedDrops[inst] = nil
end

function LootClient.getSnapshot(): Snapshot
	return snapshot
end

-- Returns an unsubscribe, matching the `() -> ()` contract the UI hooks and PanelEntry.watch expect.
function LootClient.onChanged(callback: () -> ()): () -> ()
	local token = {}
	listeners[token] = callback
	return function()
		listeners[token] = nil
	end
end

-- Pointer input. Gated because the cursor only reaches a world panel while precision focus is held;
-- otherwise it is locked to screen centre and would select whichever row it happens to rest over.
-- The pointer and wheel paths tick when they move the selection. The plates themselves do not tick on
-- hover: they can slide under a locked cursor, which would tick at random.
function LootClient.selectFromPanel(uid: string)
	if not InteractionStateController.allowsWorldPanelInteraction() then
		return
	end
	if uid ~= selectedUid then
		UISound.play("hover")
	end
	selectUid(uid)
end

-- Mouse wheel over a plate or row: +1 is the next drop (further away), -1 the previous.
function LootClient.cycleFromPanel(direction: number)
	if not InteractionStateController.allowsWorldPanelInteraction() then
		return
	end
	UISound.play("hover")
	changeSelection(direction)
end

function LootClient.pickupFromPanel(uid: string)
	if not InteractionStateController.allowsWorldPanelInteraction() then
		return
	end
	selectUid(uid)
	pickupUid(uid)
end

function LootClient.init()
	if initialized then
		return
	end
	initialized = true

	menuOpen = MenuOrchestrator.isOpen()
	-- Focus opening or closing changes how the loot is drawn and how the target is chosen.
	InteractionStateController.onChanged(function()
		refreshNearbyLoot()
	end)
	MenuOrchestrator.onChanged(function(_prev, next, _action)
		menuOpen = next.modal.open
		refreshNearbyLoot()
	end)

	for _, inst in ipairs(CollectionService:GetTagged("LootDrop")) do
		connectDrop(inst)
	end
	CollectionService:GetInstanceAddedSignal("LootDrop"):Connect(connectDrop)
	CollectionService:GetInstanceRemovedSignal("LootDrop"):Connect(disconnectDrop)

	RunService.Heartbeat:Connect(function(deltaTime: number)
		scanAccumulator += deltaTime
		if scanAccumulator < CONFIG.scanInterval then
			return
		end
		scanAccumulator = 0
		refreshNearbyLoot()
	end)

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or (CONFIG.hideWhenMenuOpen and menuOpen) then
			return
		end
		if input.KeyCode == CONFIG.interaction.pickupKey and selectedUid then
			pickupUid(selectedUid)
		end
	end)

	refreshNearbyLoot()
end

return LootClient
