--!strict
-- NotificationClient: the System's messages to the player, as a short-lived queue.
--
-- Anything can push a notice; panels/Notifications draws whatever is live. A notice pushed with the
-- `key` of one still showing merges into it -- its count goes up and its timer restarts -- so picking
-- up five potions reads as one notice counting up, not five stacked.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local SharedConfig = require(ReplicatedStorage.Shared.Config)
local UISound = require(script.Parent.Parent.UISound)

local CONFIG = SharedConfig.Notifications

export type Tone = "info" | "success" | "warning" | "error"

export type NoticeSpec = {
	-- The heading, e.g. "ITEM ACQUIRED".
	tag: string,
	tone: Tone?,
	text: string?,
	-- Rarity key and ItemGlyphs id, for a notice about an item.
	rarity: string?,
	glyph: string?,
	count: number?,
	-- Notices sharing a key merge while one is showing.
	key: string?,
}

export type Notice = {
	id: number,
	tag: string,
	tone: Tone,
	text: string?,
	rarity: string?,
	glyph: string?,
	count: number,
	key: string?,
	expiresAt: number,
}

local NotificationClient = {}

local notices: { Notice } = {}
local snapshot: { Notice } = {}
local listeners: { [{}]: () -> () } = {}
local nextId = 0
local expiry: RBXScriptConnection? = nil

local function publish()
	snapshot = table.clone(notices)
	for _, listener in pairs(listeners) do
		task.spawn(listener)
	end
end

-- Only runs while something is showing.
local function watchExpiry()
	if expiry then
		return
	end
	expiry = RunService.Heartbeat:Connect(function()
		local now = os.clock()
		local kept: { Notice } = {}
		for _, notice in ipairs(notices) do
			if notice.expiresAt > now then
				table.insert(kept, notice)
			end
		end
		if #kept ~= #notices then
			notices = kept
			publish()
		end
		if #notices == 0 and expiry then
			expiry:Disconnect()
			expiry = nil
		end
	end)
end

-- A notice's sound: errors and warnings their own, an item its rarity's pickup stinger, anything
-- else the plain stinger. A merged repeat plays again, so a run of pickups is heard as a run.
local function playFor(spec: NoticeSpec)
	if spec.tone == "error" or spec.tone == "warning" then
		UISound.play("error")
	elseif spec.rarity then
		UISound.pickup(spec.rarity)
	else
		UISound.play("notify")
	end
end

function NotificationClient.push(spec: NoticeSpec)
	local now = os.clock()
	playFor(spec)
	if spec.key then
		for index, notice in ipairs(notices) do
			if notice.key == spec.key then
				-- A fresh record rather than a mutation, so the snapshot a component holds changes.
				local merged = table.clone(notice)
				merged.count += spec.count or 1
				merged.expiresAt = now + CONFIG.duration
				notices[index] = merged
				publish()
				return
			end
		end
	end

	nextId += 1
	table.insert(notices, {
		id = nextId,
		tag = spec.tag,
		tone = spec.tone or "info",
		text = spec.text,
		rarity = spec.rarity,
		glyph = spec.glyph,
		count = spec.count or 1,
		key = spec.key,
		expiresAt = now + CONFIG.duration,
	})
	while #notices > CONFIG.max do
		table.remove(notices, 1)
	end
	publish()
	watchExpiry()
end

-- Oldest first.
function NotificationClient.getSnapshot(): { Notice }
	return snapshot
end

function NotificationClient.onChanged(callback: () -> ()): () -> ()
	local token = {}
	listeners[token] = callback
	return function()
		listeners[token] = nil
	end
end

return NotificationClient
