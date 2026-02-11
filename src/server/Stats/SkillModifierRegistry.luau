--!strict

-- Minimal registry for skill query modifiers per entity and event.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SkillQueryTypes = require(ReplicatedStorage.Shared.skills.SkillQueryTypes)

export type SkillModifier = SkillQueryTypes.SkillModifier

local Registry: {
	[string]: { -- entityId
		[string]: { SkillModifier }, -- event -> list of modifiers
	},
} = {}

local SkillModifierRegistry = {}
local listeners: { (string, string, string) -> () } = {} -- entityId, event, modifierId

function SkillModifierRegistry.onChanged(callback: (string, string, string) -> ())
	table.insert(listeners, callback)
	return function()
		for i, cb in ipairs(listeners) do
			if cb == callback then
				table.remove(listeners, i)
				break
			end
		end
	end
end

function SkillModifierRegistry.register(entityId: string, event: string, modifier: SkillModifier)
	local byEvent = Registry[entityId]
	if not byEvent then
		byEvent = {}
		Registry[entityId] = byEvent
	end
	local list = byEvent[event]
	if not list then
		list = {}
		byEvent[event] = list
	end
	table.insert(list, modifier)
	-- Keep deterministic order by priority then id
	table.sort(list, function(a: SkillModifier, b: SkillModifier)
		if a.priority == b.priority then
			return a.id < b.id
		end
		return a.priority < b.priority
	end)
	for _, cb in ipairs(listeners) do
		task.spawn(function()
			local ok, err = pcall(cb, entityId, event, modifier.id)
			if not ok then
				warn("[SkillModifierRegistry] listener error:", err)
			end
		end)
	end
end

function SkillModifierRegistry.unregister(entityId: string, event: string, modifierId: string)
	local byEvent = Registry[entityId]
	if not byEvent then
		return
	end
	local list = byEvent[event]
	if not list then
		return
	end
	for i = #list, 1, -1 do
		if list[i].id == modifierId then
			table.remove(list, i)
		end
	end
	if #list == 0 then
		byEvent[event] = nil
	end
	if next(byEvent) == nil then
		Registry[entityId] = nil
	end
	for _, cb in ipairs(listeners) do
		task.spawn(function()
			local ok, err = pcall(cb, entityId, event, modifierId)
			if not ok then
				warn("[SkillModifierRegistry] listener error:", err)
			end
		end)
	end
end

function SkillModifierRegistry.getModifiers(entityId: string, event: string): { SkillModifier }
	local byEvent = Registry[entityId]
	if not byEvent then
		return {}
	end
	local list = byEvent[event]
	if not list then
		return {}
	end
	return list
end

return SkillModifierRegistry
