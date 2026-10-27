--!strict
-- MasteryCanvasController: whether the mastery canvas is open and which track it shows.
--
-- The canvas is a full-screen overlay rather than a menu view: the menu's views are panels staged
-- beside the character, and the canvas is the System's inner view, the world blurred out behind it.
-- Opening it takes input the way the menu does (a named overlay on InteractionStateController) and
-- closes the menu; the menu opening closes the canvas, so the two never stack.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local MasteryTracks = require(ReplicatedStorage.Shared.progression.MasteryTracks)
local BasicAttackProfileRegistry = require(ReplicatedStorage.Shared.skills.BasicAttackProfileRegistry)
local InteractionStateController = require(script.Parent.Parent.Parent.input.InteractionStateController)
local CombatLoadoutMirror = require(script.Parent.Parent.Parent.Inventory.CombatLoadoutMirror)
local MenuOrchestrator = require(script.Parent.Parent.menu.MenuOrchestrator)
local UISound = require(script.Parent.Parent.UISound)

local OVERLAY_NAME = "MasteryCanvas"
local BLUR_SIZE = 18
local BLUR_TIME = 0.28

export type State = {
	open: boolean,
	track: string,
}

local MasteryCanvasController = {}

local state: State = { open = false, track = MasteryTracks.list()[1].id }
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

function MasteryCanvasController.open(trackId: string?)
	local track = trackId or heldTrack() or state.track
	if state.open and state.track == track then
		return
	end
	local wasOpen = state.open
	state = { open = true, track = if MasteryTracks.get(track) then track else state.track }
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
	state = { open = false, track = state.track }
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
	state = { open = true, track = trackId }
	publish()
end

MenuOrchestrator.onChanged(function(_previous, nextState)
	if nextState.modal.open then
		MasteryCanvasController.close()
	end
end)

return MasteryCanvasController
