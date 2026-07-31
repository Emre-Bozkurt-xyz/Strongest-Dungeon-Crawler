--!strict
-- Container for the skill bar: reads the active profile's filled slots plus the two signals shared
-- across every slot (global cooldown, blocked cast), and hands a plain view model to SkillBar.
--
-- `script` here IS the SkillSlotContainer module (init.luau collapses into its folder), so Parent is
-- `panels` and Parent.Parent is `ui`. SkillBar and SkillSlotButton, being children, need one more
-- level than this (see the init.luau trap in docs/tasks/ui-migration-plan.md).
--
-- Screen-space (registered in ScreenRegistry), not a world panel: there is no visibility predicate
-- and no surface to create or fade. It always renders; an empty profile just renders an empty bar,
-- matching SkillSlotUI's old behaviour of only ever drawing filled slots. Takes no props, per the
-- container convention every other panel in this codebase follows.

local React = require(game:GetService("ReplicatedStorage").Packages.React)

local useSkillSlots = require(script.Parent.Parent.hooks.useSkillSlots)
local useGlobalCooldown = require(script.Parent.Parent.hooks.useGlobalCooldown)
local useCastBlocked = require(script.Parent.Parent.hooks.useCastBlocked)
local useActiveSkill = require(script.Parent.Parent.hooks.useActiveSkill)
local Selector = require(script.Parent.Parent.selectors.skillSlots)
local SkillBar = require(script.SkillBar)

local e = React.createElement

local function SkillSlotContainer()
	local filled = useSkillSlots()
	local gcdProgress = useGlobalCooldown()
	local castBlocked = useCastBlocked()
	local activeSkill = useActiveSkill()

	local slots = Selector.buildSlots(filled)

	return e(SkillBar, {
		slots = slots,
		gcdProgress = gcdProgress,
		castBlocked = castBlocked,
		activeSkill = activeSkill,
	})
end

return SkillSlotContainer
