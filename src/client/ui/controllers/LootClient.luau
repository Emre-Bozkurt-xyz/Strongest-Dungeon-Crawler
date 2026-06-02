--!strict
-- LootClient: tracks nearby loot, drives WorldLootInspectPanel, and handles selected-row pickup.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local InventoryClient = require(script.Parent.Parent.Parent.Inventory.InventoryClient)
local InteractionStateController = require(script.Parent.Parent.Parent.input.InteractionStateController)
local MenuOrchestrator = require(script.Parent.Parent.menu.MenuOrchestrator)
local WorldLootInspectRuntime = require(script.Parent.Parent.runtime.WorldLootInspectRuntime)
local SharedConfig = require(ReplicatedStorage.Shared.Config)

local LootClient = {}

type LootEntry = WorldLootInspectRuntime.LootEntry

type TrackedDrop = {
	part: BasePart,
	prompt: ProximityPrompt?,
}

local CONFIG = SharedConfig.WorldLootInspect
local player = Players.LocalPlayer

local trackedDrops: { [BasePart]: TrackedDrop } = {}
local nearbyEntries = {} :: { LootEntry }
local selectedUid = nil :: string?
local selectedIndex = 1
local runtime = nil :: any
local heartbeatConnection = nil :: RBXScriptConnection?
local inputBeganConnection = nil :: RBXScriptConnection?
local menuConnection = nil :: (() -> ())?
local scanAccumulator = 0
local menuOpen = false
local nextPickupAt = 0
local nextRuntimeRetryAt = 0
local initialized = false

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

local function syncPromptEnabled(prompt: ProximityPrompt?, enabled: boolean)
	if not prompt then
		return
	end
	pcall(function()
		prompt.Enabled = enabled
	end)
end

local function syncAllPrompts()
	local enablePrompt = runtime == nil and not (CONFIG.hideWhenMenuOpen and menuOpen)
	for _, tracked in pairs(trackedDrops) do
		syncPromptEnabled(tracked.prompt, enablePrompt)
	end
end

local function ensureRuntime()
	if runtime then
		return runtime
	end
	if os.clock() < nextRuntimeRetryAt then
		return nil
	end
	nextRuntimeRetryAt = os.clock() + 2
	runtime = WorldLootInspectRuntime.tryInit()
	if runtime then
		syncAllPrompts()
	end
	return runtime
end

local function pickupEntry(index: number)
	if os.clock() < nextPickupAt then
		return
	end
	local entry = nearbyEntries[index]
	if not entry then
		return
	end
	selectedIndex = index
	selectedUid = entry.uid
	nextPickupAt = os.clock() + 0.15
	InventoryClient.requestAction({
		action = "pickup",
		uid = entry.uid,
	})
end

local function selectEntry(index: number): boolean
	local entry = nearbyEntries[index]
	if not entry then
		return false
	end
	if selectedUid == entry.uid and selectedIndex == index then
		return false
	end
	selectedIndex = index
	selectedUid = entry.uid
	return true
end

local function getRuntimeCallbacks()
	return {
		onSelect = function(index: number, _entry: LootEntry)
			if not InteractionStateController.allowsWorldPanelInteraction() then
				return
			end
			if selectEntry(index) then
				local inst = ensureRuntime()
				if inst then
					inst:setSelectedIndex(selectedIndex)
				end
			end
		end,
		onPickup = function(index: number, _entry: LootEntry)
			if not InteractionStateController.allowsWorldPanelInteraction() then
				return
			end
			if selectEntry(index) then
				local inst = ensureRuntime()
				if inst then
					inst:setSelectedIndex(selectedIndex)
				end
			end
			pickupEntry(index)
		end,
	}
end

local function syncRuntime()
	local inst = ensureRuntime()
	if not inst then
		return
	end
	inst:setEntries(nearbyEntries, selectedIndex, getRuntimeCallbacks())
end

local function refreshNearbyLoot()
	local inst = runtime
	syncAllPrompts()
	local root = getPlayerRoot()
	if not root or (CONFIG.hideWhenMenuOpen and menuOpen) then
		nearbyEntries = {}
		selectedUid = nil
		selectedIndex = 1
		if inst then
			inst:clear()
		end
		return
	end

	local entries: { LootEntry } = {}
	for part, tracked in pairs(trackedDrops) do
		if not part.Parent then
			trackedDrops[part] = nil
		else
			tracked.prompt = part:FindFirstChildWhichIsA("ProximityPrompt", true)
			local entry = getDropEntry(part, root)
			if entry then
				table.insert(entries, entry)
			end
		end
	end

	sortEntries(entries)
	nearbyEntries = entries

	if #nearbyEntries == 0 then
		selectedUid = nil
		selectedIndex = 1
		if inst then
			inst:clear()
		end
		return
	end

	local matchedIndex = nil :: number?
	if selectedUid then
		for index, entry in ipairs(nearbyEntries) do
			if entry.uid == selectedUid then
				matchedIndex = index
				break
			end
		end
	end
	selectedIndex = matchedIndex or 1
	selectedUid = nearbyEntries[selectedIndex].uid

	inst = inst or ensureRuntime()
	if inst then
		syncRuntime()
	end
end

local function changeSelection(direction: number)
	local count = #nearbyEntries
	if count == 0 then
		return
	end

	local nextIndex = selectedIndex + direction
	if CONFIG.selectionWrap then
		if nextIndex < 1 then
			nextIndex = count
		elseif nextIndex > count then
			nextIndex = 1
		end
	else
		nextIndex = math.clamp(nextIndex, 1, count)
	end

	selectedIndex = nextIndex
	selectedUid = nearbyEntries[selectedIndex].uid
	local inst = ensureRuntime()
	if inst then
		inst:setSelectedIndex(selectedIndex)
	end
end

local function pickupSelected()
	pickupEntry(selectedIndex)
end

local function connectDrop(inst: Instance)
	if not inst:IsA("BasePart") then
		return
	end
	local prompt = inst:FindFirstChildWhichIsA("ProximityPrompt", true)
	trackedDrops[inst] = {
		part = inst,
		prompt = prompt,
	}
	if runtime then
		syncPromptEnabled(prompt, false)
	end
end

local function disconnectDrop(inst: Instance)
	if not inst:IsA("BasePart") then
		return
	end
	local tracked = trackedDrops[inst]
	if tracked then
		syncPromptEnabled(tracked.prompt, true)
	end
	trackedDrops[inst] = nil
end

function LootClient.init()
	if initialized then
		return
	end
	initialized = true

	menuOpen = MenuOrchestrator.isOpen()
	menuConnection = MenuOrchestrator.onChanged(function(_prev, next, _action)
		menuOpen = next.modal.open
		refreshNearbyLoot()
	end)

	for _, inst in ipairs(CollectionService:GetTagged("LootDrop")) do
		connectDrop(inst)
	end
	CollectionService:GetInstanceAddedSignal("LootDrop"):Connect(connectDrop)
	CollectionService:GetInstanceRemovedSignal("LootDrop"):Connect(disconnectDrop)

	heartbeatConnection = RunService.Heartbeat:Connect(function(deltaTime: number)
		scanAccumulator += deltaTime
		if scanAccumulator < CONFIG.scanInterval then
			return
		end
		scanAccumulator = 0
		refreshNearbyLoot()
	end)

	inputBeganConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or (CONFIG.hideWhenMenuOpen and menuOpen) then
			return
		end
		if input.KeyCode == CONFIG.interaction.pickupKey then
			pickupSelected()
			return
		end
		if input.KeyCode == Enum.KeyCode.Up then
			changeSelection(-1)
			return
		end
		if input.KeyCode == Enum.KeyCode.Down then
			changeSelection(1)
		end
	end)

	refreshNearbyLoot()
end

return LootClient
