--!strict
-- MasteryCanvasController: whether the mastery canvas is open and which track it shows.
--
-- The canvas is a full-screen overlay rather than a menu view: the menu's views are panels staged
-- beside the character, and the canvas is the System's inner view, the world blurred out behind it.
-- Opening it takes input the way the menu does (a named overlay on InteractionStateController) and
-- closes the menu; the menu opening closes the canvas, so the two never stack.
--
-- At an Attunement Shrine (its prompt, from AttunementService) the canvas opens in shrine mode,
-- where the shown track can be attuned or released. Shrine mode ends when the player walks out of
-- range; the server checks the distance again on every change.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local MasteryTracks = require(ReplicatedStorage.Shared.progression.MasteryTracks)
local Attunement = require(ReplicatedStorage.Shared.progression.Attunement)
local BasicAttackProfileRegistry = require(ReplicatedStorage.Shared.skills.BasicAttackProfileRegistry)
local InteractionStateController = require(script.Parent.Parent.Parent.input.InteractionStateController)
local CombatLoadoutMirror = require(script.Parent.Parent.Parent.Inventory.CombatLoadoutMirror)
local MenuOrchestrator = require(script.Parent.Parent.menu.MenuOrchestrator)
local UISound = require(script.Parent.Parent.UISound)

local OVERLAY_NAME = "MasteryCanvas"
local BLUR_SIZE = 18
local BLUR_TIME = 0.28
-- Must match the server's prompt name (AttunementService).
local SHRINE_PROMPT = "AttunementPrompt"

export type State = {
	open: boolean,
	track: string,
	-- The shrine the canvas was opened at, while the player is still in its range.
	shrine: Instance?,
}

local MasteryCanvasController = {}

local state: State = { open = false, track = MasteryTracks.list()[1].id, shrine = nil }
local listeners: { [{}]: () -> () } = {}
local blur: BlurEffect? = nil

local function publish()
	for _, listener in pairs(listeners) do
		task.spawn(listener)
	end
end

-- The world goes soft behind the canvas so the tree reads as being somewhere else.
local function setBlur(on: boolean)
	if not blur then
		local effect = Instance.new("BlurEffect")
		effect.Name = "MasteryCanvasBlur"
		effect.Size = 0
		effect.Parent = Lighting
		blur = effect
	end
	TweenService:Create(
		blur :: BlurEffect,
		TweenInfo.new(BLUR_TIME, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{ Size = if on then BLUR_SIZE else 0 }
	):Play()
end

-- The weapon context the player is in: the held weapon's class, or "unarmed". Forms are chosen per
-- context, so the canvas offers the ones that fit what is held.
function MasteryCanvasController.context(): string
	return BasicAttackProfileRegistry.classKeyOf(CombatLoadoutMirror.get())
end

-- The track for what the player is holding, so opening the canvas shows the weapon in hand.
local function heldTrack(): string?
	local track = MasteryTracks.forContext(MasteryCanvasController.context())
	return track and track.id
end

function MasteryCanvasController.get(): State
	return state
end

function MasteryCanvasController.onChanged(callback: () -> ()): () -> ()
	local key = {}
	listeners[key] = callback
	return function()
		listeners[key] = nil
	end
end

local function inRange(shrine: Instance): boolean
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local position = if shrine:IsA("Model")
		then shrine:GetPivot().Position
		elseif shrine:IsA("BasePart") then shrine.Position
		else nil
	return root ~= nil and position ~= nil and shrine.Parent ~= nil
		and (position - root.Position).Magnitude <= Attunement.SHRINE_RANGE
end

-- Ends shrine mode once the player leaves the shrine (or it goes away); the canvas stays open.
local function watchShrine(shrine: Instance)
	task.spawn(function()
		while state.shrine == shrine do
			if not inRange(shrine) then
				state = { open = state.open, track = state.track, shrine = nil }
				publish()
				return
			end
			task.wait(0.25)
		end
	end)
end

-- `shrine`: open in shrine mode, at that shrine.
function MasteryCanvasController.open(trackId: string?, shrine: Instance?)
	local track = trackId or heldTrack() or state.track
	local atShrine = shrine or (if state.open then state.shrine else nil)
	if state.open and state.track == track and state.shrine == atShrine then
		return
	end
	local wasOpen = state.open
	state = { open = true, track = if MasteryTracks.get(track) then track else state.track, shrine = atShrine }
	if shrine then
		watchShrine(shrine)
	end
	if not wasOpen then
		if MenuOrchestrator.isOpen() then
			MenuOrchestrator.close()
		end
		InteractionStateController.setOverlayOpen(OVERLAY_NAME, true)
		setBlur(true)
		UISound.play("open")
	end
	publish()
end

function MasteryCanvasController.close()
	if not state.open then
		return
	end
	state = { open = false, track = state.track, shrine = nil }
	InteractionStateController.setOverlayOpen(OVERLAY_NAME, false)
	setBlur(false)
	UISound.play("close")
	publish()
end

function MasteryCanvasController.toggle()
	if state.open then
		MasteryCanvasController.close()
	else
		MasteryCanvasController.open()
	end
end

function MasteryCanvasController.setTrack(trackId: string)
	if not state.open or state.track == trackId or not MasteryTracks.get(trackId) then
		return
	end
	state = { open = true, track = trackId, shrine = state.shrine }
	publish()
end

-- The shrine's prompt is the server's; triggering it opens the canvas here.
ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
	if prompt.Name ~= SHRINE_PROMPT then
		return
	end
	local shrine = prompt.Parent
	while shrine and not CollectionService:HasTag(shrine, Attunement.SHRINE_TAG) do
		shrine = shrine.Parent
	end
	if shrine then
		MasteryCanvasController.open(nil, shrine)
	end
end)

MenuOrchestrator.onChanged(function(_previous, nextState)
	if nextState.modal.open then
		MasteryCanvasController.close()
	end
end)

return MasteryCanvasController
