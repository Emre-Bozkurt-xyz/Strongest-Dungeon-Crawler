--!strict
-- Thin client-side mirror of the current combat loadout snapshot.
--
-- InventoryClient feeds this module whenever a new snapshot arrives from the server; client
-- skill code reads from here instead of requiring InventoryClient directly. This keeps the
-- ownership boundary clean (skills own skill prediction, inventory owns inventory state) and
-- gives client-side tempo prediction a stable, decoupled source (see Phase A / A4 in
-- docs/tasks/equipment-item-architecture.md).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemTypes = require(ReplicatedStorage.Shared.items.ItemTypes)

local CombatLoadoutMirror = {}

local current: ItemTypes.CombatLoadoutSnapshot? = nil

function CombatLoadoutMirror.set(snapshot: ItemTypes.CombatLoadoutSnapshot?)
	current = snapshot
end

function CombatLoadoutMirror.get(): ItemTypes.CombatLoadoutSnapshot?
	return current
end

-- Convenience accessor for the most common client read: the main-hand weapon's attack speed,
-- used to predict tempo the same way SkillTimingService does on the server (D3).
function CombatLoadoutMirror.getMainAttackSpeed(): number?
	if current and current.main then
		return current.main.attackSpeed
	end
	return nil
end

return CombatLoadoutMirror
