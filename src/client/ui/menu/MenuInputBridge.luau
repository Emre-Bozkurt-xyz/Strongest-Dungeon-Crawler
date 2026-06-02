--!strict

local InteractionStateController = require(script.Parent.Parent.Parent.input.InteractionStateController)

local MenuInputBridge = {}

function MenuInputBridge.apply(modalOpen: boolean)
	InteractionStateController.setModalOpen(modalOpen)
end

function MenuInputBridge.isGameplayBlocked(): boolean
	return InteractionStateController.isGameplayBlocked()
end

return MenuInputBridge
