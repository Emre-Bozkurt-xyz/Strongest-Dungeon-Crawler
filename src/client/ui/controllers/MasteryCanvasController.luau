--!strict
-- MasteryCanvasController: whether the mastery mind-space is open, and whether it shows the menu
-- of masteries or one mastery's tree (docs/planning/mastery-mind-space.md).
--
-- The canvas is a full-screen overlay rather than a menu view: the menu's views are panels staged
-- beside the character, and the canvas is the System's inner view, the world blurred out behind it.
-- Opening it takes input the way the menu does (a named overlay on InteractionStateController) and
-- closes the menu; the menu opening closes the canvas, so the two never stack.
--
-- At an Attunement Shrine (its prompt, from AttunementService) the menu opens in shrine mode, where
-- choosing a mastery attunes it. Shrine mode ends when the player walks out of
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

export type View = "menu" | "tree"

export type State = {
	open: boolean,
	view: View,
	-- The tree shown, or last shown.
	track: string,
	-- The shrine the canvas was opened at, while the player is still in its range.
	shrine: Instance?,
}

local MasteryCanvasController = {}

local state: State = { open = false, view = "menu", track = MasteryTracks.list()[1].id, shrine = nil }
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
				state = { open = state.open, view = state.view, track = state.track, shrine = nil }
				publish()
				return
			end
			task.wait(0.25)
		end
	end)
end

-- Opens on the menu, or straight into `trackId`'s tree. `shrine`: open in shrine mode, at that shrine.
function MasteryCanvasController.open(trackId: string?, shrine: Instance?)
	local atShrine = shrine or (if state.open then state.shrine else nil)
	local view: View = if trackId and MasteryTracks.get(trackId) then "tree" else "menu"
	local track = if view == "tree" then trackId :: string else state.track
	if state.open and state.view == view and state.track == track and state.shrine == atShrine then
		return
	end
	local wasOpen = state.open
	state = { open = true, view = view, track = track, shrine = atShrine }
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
	state = { open = false, view = "menu", track = state.track, shrine = nil }
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

-- Zooms from the menu into a mastery's tree.
function MasteryCanvasController.setTrack(trackId: string)
	if not state.open or not MasteryTracks.get(trackId) or (state.view == "tree" and state.track == trackId) then
		return
	end
	state = { open = true, view = "tree", track = trackId, shrine = state.shrine }
	publish()
end

-- Back out of a tree to the menu.
function MasteryCanvasController.back()
	if not state.open or state.view == "menu" then
		return
	end
	state = { open = true, view = "menu", track = state.track, shrine = state.shrine }
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
