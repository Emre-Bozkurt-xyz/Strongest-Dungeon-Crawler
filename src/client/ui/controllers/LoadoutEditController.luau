--!strict
-- LoadoutEditController: what the player is in the middle of on the Loadout, shared by its two panels.
--
-- The slot bar and the skills list are separate surfaces with separate React roots, and a skill goes
-- from one to the other, so the picked slot, the held skill and a drag in progress live here rather
-- than in either panel. Placing works three ways, all ending in `place`: drag a skill onto a slot, or
-- click a slot and then a skill, or a skill and then a slot. The clicks are what a gamepad or touch
-- screen uses; the drag is LoadoutDragController's.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local LoadoutTypes = require(ReplicatedStorage.Shared.skills.LoadoutTypes)

local SkillSlots = require(script.Parent.Parent.Parent.SkillsFramework.SkillSlots)
local UISound = require(script.Parent.Parent.UISound)

export type Drag = {
	skill: string,
	-- The slot it was lifted out of, for a drag that started on the bar.
	from: number?,
}

export type State = {
	-- The set being edited, which is also the set fought with.
	editingSet: number,
	-- A slot waiting for a skill.
	picked: number?,
	-- A skill waiting for a slot.
	held: string?,
	-- The skill the skills panel describes when nothing is under the pointer: the last one chosen.
	shown: string?,
	hovered: string?,
	dragging: Drag?,
	-- The open slot under a drag.
	dropSlot: number?,
}

local LoadoutEditController = {}

local state: State = {
	editingSet = SkillSlots.getActiveSet(),
	picked = nil,
	held = nil,
	shown = nil,
	hovered = nil,
	dragging = nil,
	dropSlot = nil,
}
local listeners: { [{}]: () -> () } = {}

local function update(patch: { [string]: any })
	local nextState = table.clone(state) :: any
	for key, value in pairs(patch) do
		nextState[key] = value
	end
	-- `false` in a patch clears a field: a nil value would not survive the pairs above.
	for key, value in pairs(nextState) do
		if value == false and key ~= "editingSet" then
			nextState[key] = nil
		end
	end
	state = nextState
	for _, listener in pairs(listeners) do
		task.spawn(listener)
	end
end

function LoadoutEditController.get(): State
	return state
end

function LoadoutEditController.onChanged(callback: () -> ()): () -> ()
	local key = {}
	listeners[key] = callback
	return function()
		listeners[key] = nil
	end
end

function LoadoutEditController.use(): State
	local value, setValue = React.useState(LoadoutEditController.get)
	React.useEffect(function()
		local disconnect = LoadoutEditController.onChanged(function()
			setValue(LoadoutEditController.get())
		end)
		setValue(LoadoutEditController.get())
		return disconnect
	end, {})
	return value
end

local function slotOpen(slot: number): boolean
	return slot <= SkillSlots.limits().slots
end

local function skillIn(slot: number): string?
	local slots = SkillSlots.getSet(state.editingSet)
	local skill = slots and slots[slot]
	return if skill and skill ~= LoadoutTypes.EMPTY then skill else nil
end

function LoadoutEditController.setEditingSet(set: number)
	UISound.play("confirm")
	-- The set being edited is the one fought with: one idea, not two.
	SkillSlots.setActiveSet(set)
	update({ editingSet = set, picked = false, held = false })
end

-- Put `skill` in `slot` of the set being edited. A skill already elsewhere in the set swaps with
-- whatever the slot held (LoadoutRules).
function LoadoutEditController.place(slot: number, skill: string)
	if not slotOpen(slot) then
		return
	end
	if skillIn(slot) ~= skill then
		UISound.play("slotAssign")
		SkillSlots.assign(slot, skill, state.editingSet)
	end
	update({ picked = false, held = false, shown = skill })
end

function LoadoutEditController.clear(slot: number)
	if not slotOpen(slot) or not skillIn(slot) then
		return
	end
	UISound.play("confirm")
	SkillSlots.clear(slot, state.editingSet)
	update({ picked = false })
end

-- A click on a slot: drops the held skill there, or picks the slot (again lets go of it).
function LoadoutEditController.activateSlot(slot: number)
	if not slotOpen(slot) then
		return
	end
	local held = state.held
	if held then
		LoadoutEditController.place(slot, held)
		return
	end
	UISound.play("confirm")
	local inSlot = skillIn(slot)
	update({
		picked = if state.picked == slot then false else slot,
		shown = inSlot or state.shown or false,
	})
end

-- A click on a skill: fills the picked slot, or holds the skill (again lets go of it).
function LoadoutEditController.activateSkill(skill: string)
	local picked = state.picked
	if picked then
		LoadoutEditController.place(picked, skill)
		return
	end
	UISound.play("confirm")
	update({ held = if state.held == skill then false else skill, shown = skill })
end

function LoadoutEditController.setHovered(skill: string?)
	if state.hovered ~= skill then
		update({ hovered = skill or false })
	end
end

function LoadoutEditController.setDrag(drag: Drag?, dropSlot: number?)
	if state.dragging == drag and state.dropSlot == dropSlot then
		return
	end
	update({ dragging = drag or false, dropSlot = dropSlot or false })
end

-- Leaving the Loadout lets go of anything picked, held or carried.
function LoadoutEditController.reset()
	if state.picked or state.held or state.dragging or state.hovered then
		update({ picked = false, held = false, dragging = false, dropSlot = false, hovered = false })
	end
end

-- The set fought with can change from outside (the HUD cycles sets, the save arrives, a level opens
-- or closes a set); the Loadout follows it.
local function follow()
	local active = SkillSlots.getActiveSet()
	if active ~= state.editingSet then
		update({ editingSet = active, picked = false, held = false })
	end
end
SkillSlots.onActiveSetChanged(follow)
SkillSlots.onSlotsChanged(follow)

return LoadoutEditController
