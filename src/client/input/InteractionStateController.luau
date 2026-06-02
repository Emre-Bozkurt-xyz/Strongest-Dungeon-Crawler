--!strict
-- Central interaction policy resolver for camera mode, modal menu, and temporary world-panel interaction.

local InteractionStateController = {}

export type CameraMode = "Free" | "OverShoulder"
export type ActiveSurface = "Gameplay" | "WorldPanel" | "ModalUI"

export type State = {
	cameraMode: CameraMode,
	modalOpen: boolean,
	precisionFocusHeld: boolean,
	cursorUnlocked: boolean,
	lookInputSuppressed: boolean,
	gameplayBlocked: boolean,
	allowsModalInteraction: boolean,
	allowsWorldPanelInteraction: boolean,
	activeSurface: ActiveSurface,
}

local changeEvent = Instance.new("BindableEvent")

local initialized = false
local rawCameraMode: CameraMode = "OverShoulder"
local rawModalOpen = false
local rawPrecisionFocusHeld = false
local lastAppliedCursorUnlocked = nil :: boolean?

local currentState: State = {
	cameraMode = rawCameraMode,
	modalOpen = rawModalOpen,
	precisionFocusHeld = rawPrecisionFocusHeld,
	cursorUnlocked = false,
	lookInputSuppressed = false,
	gameplayBlocked = false,
	allowsModalInteraction = false,
	allowsWorldPanelInteraction = false,
	activeSurface = "Gameplay",
}

local function cloneState(state: State): State
	return {
		cameraMode = state.cameraMode,
		modalOpen = state.modalOpen,
		precisionFocusHeld = state.precisionFocusHeld,
		cursorUnlocked = state.cursorUnlocked,
		lookInputSuppressed = state.lookInputSuppressed,
		gameplayBlocked = state.gameplayBlocked,
		allowsModalInteraction = state.allowsModalInteraction,
		allowsWorldPanelInteraction = state.allowsWorldPanelInteraction,
		activeSurface = state.activeSurface,
	}
end

local function statesEqual(a: State, b: State): boolean
	return a.cameraMode == b.cameraMode
		and a.modalOpen == b.modalOpen
		and a.precisionFocusHeld == b.precisionFocusHeld
		and a.cursorUnlocked == b.cursorUnlocked
		and a.lookInputSuppressed == b.lookInputSuppressed
		and a.gameplayBlocked == b.gameplayBlocked
		and a.allowsModalInteraction == b.allowsModalInteraction
		and a.allowsWorldPanelInteraction == b.allowsWorldPanelInteraction
		and a.activeSurface == b.activeSurface
end

local function deriveState(): State
	local allowsModalInteraction = rawModalOpen
	local allowsWorldPanelInteraction = (not rawModalOpen) and rawPrecisionFocusHeld
	local cursorUnlocked = allowsModalInteraction or allowsWorldPanelInteraction
	local lookInputSuppressed = rawCameraMode == "OverShoulder" and cursorUnlocked
	local gameplayBlocked = allowsModalInteraction
	local activeSurface: ActiveSurface = if allowsModalInteraction
		then "ModalUI"
		else if allowsWorldPanelInteraction then "WorldPanel" else "Gameplay"

	return {
		cameraMode = rawCameraMode,
		modalOpen = rawModalOpen,
		precisionFocusHeld = rawPrecisionFocusHeld,
		cursorUnlocked = cursorUnlocked,
		lookInputSuppressed = lookInputSuppressed,
		gameplayBlocked = gameplayBlocked,
		allowsModalInteraction = allowsModalInteraction,
		allowsWorldPanelInteraction = allowsWorldPanelInteraction,
		activeSurface = activeSurface,
	}
end

local function applyCursorPolicy(nextState: State)
	if lastAppliedCursorUnlocked == nextState.cursorUnlocked then
		return
	end

	local ok, CameraController = pcall(require, script.Parent.Parent.CameraController)
	if ok and CameraController and CameraController.getInstance then
		CameraController.getInstance():setCursorUnlocked(nextState.cursorUnlocked)
		lastAppliedCursorUnlocked = nextState.cursorUnlocked
	end
end

local function recompute(reason: string)
	local previous = cloneState(currentState)
	local nextState = deriveState()
	currentState = nextState
	applyCursorPolicy(nextState)
	if not statesEqual(previous, nextState) then
		changeEvent:Fire(previous, cloneState(nextState), reason)
	end
end

function InteractionStateController.init()
	if initialized then
		return
	end
	initialized = true
	recompute("init")
end

function InteractionStateController.setCameraMode(mode: CameraMode)
	if rawCameraMode == mode then
		return
	end
	rawCameraMode = mode
	recompute("camera_mode")
end

function InteractionStateController.setModalOpen(open: boolean)
	local nextOpen = open and true or false
	local changed = rawModalOpen ~= nextOpen
	local clearedPrecisionFocus = rawPrecisionFocusHeld
	if not changed and not clearedPrecisionFocus then
		return
	end
	rawModalOpen = nextOpen
	rawPrecisionFocusHeld = false
	recompute("modal_open")
end

function InteractionStateController.setPrecisionFocusHeld(held: boolean)
	if rawPrecisionFocusHeld == held then
		return
	end
	rawPrecisionFocusHeld = held and true or false
	recompute("precision_focus")
end

function InteractionStateController.getState(): State
	return cloneState(currentState)
end

function InteractionStateController.isCursorUnlocked(): boolean
	return currentState.cursorUnlocked
end

function InteractionStateController.isGameplayBlocked(): boolean
	return currentState.gameplayBlocked
end

function InteractionStateController.allowsModalInteraction(): boolean
	return currentState.allowsModalInteraction
end

function InteractionStateController.allowsWorldPanelInteraction(): boolean
	return currentState.allowsWorldPanelInteraction
end

function InteractionStateController.isPrecisionFocusActive(): boolean
	return currentState.allowsWorldPanelInteraction
end

function InteractionStateController.onChanged(callback: (State, State, string) -> ()): () -> ()
	local connection = changeEvent.Event:Connect(callback)
	return function()
		connection:Disconnect()
	end
end

return InteractionStateController
