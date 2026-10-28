--!strict
-- Words for what a passive node does (NodeEffects), filled with live numbers, for the mastery
-- canvas's tooltips (docs/planning/mastery-mind-space.md, "Technical notes").
--
-- One template per effect kind, and one phrase per filter field, rather than text per node: the
-- text is built from the same data the server applies, so retuning a number never leaves a stale
-- description behind. Only the fields a kind grows are multiplied by the node's scale
-- (server/Progression/Passives/Kinds); chances, durations and radii read as authored.

local NodeEffects = require(script.Parent.NodeEffects)

type Effect = NodeEffects.Effect
type Filter = NodeEffects.Filter

local EffectText = {}

local function percent(value: number): string
	local rounded = math.floor(value * 1000 + 0.5) / 10
	return if rounded == math.floor(rounded) then `{math.floor(rounded)}%` else `{rounded}%`
end

local function number(value: number): string
	local rounded = math.floor(value * 10 + 0.5) / 10
	return if rounded == math.floor(rounded) then tostring(math.floor(rounded)) else tostring(rounded)
end

local function seconds(value: number): string
	return `{number(value)}s`
end

-- "FirePenetration" -> "fire penetration".
local function spaced(name: string): string
	return string.lower((string.gsub(name, "(%l)(%u)", "%1 %2")))
end

local function statusName(status: string): string
	return string.upper(string.sub(status, 1, 1)) .. string.sub(status, 2)
end

local function list(items: { string }): string
	if #items <= 1 then
		return items[1] or ""
	end
	return table.concat(items, ", ", 1, #items - 1) .. " or " .. items[#items]
end

-- The weapon groups NodeEffects names, read as one word rather than a list of classes.
local GROUPS: { { name: string, members: { string } } } = {
	{ name = "blades", members = { "sword", "dagger", "axe", "greatsword" } },
	{ name = "blunt weapons and fists", members = { "unarmed", "mace", "hammer" } },
	{ name = "maces and hammers", members = { "mace", "hammer" } },
	{ name = "bows", members = { "bow" } },
	{ name = "bare fists", members = { "unarmed" } },
}

local function sameSet(a: { string }, b: { string }): boolean
	if #a ~= #b then
		return false
	end
	for _, value in ipairs(a) do
		if not table.find(b, value) then
			return false
		end
	end
	return true
end

local function contextPhrase(contexts: { string }): string
	for _, group in ipairs(GROUPS) do
		if sameSet(contexts, group.members) then
			return `with {group.name}`
		end
	end
	local names: { string } = {}
	for _, context in ipairs(contexts) do
		table.insert(names, if context == "unarmed" then "fists" else `{context}s`)
	end
	return `with {list(names)}`
end

local DELIVERY: { [string]: string } = { melee = "melee hits", projectile = "projectiles", area = "area hits" }

-- When an effect applies, as trailing phrases. `damageTypes` is left to the kind's own wording
-- where it reads better there.
local function filterPhrases(filter: Filter?, skipTypes: boolean?): { string }
	local out: { string } = {}
	if not filter then
		return out
	end
	if filter.damageTypes and not skipTypes then
		table.insert(out, `on {list(filter.damageTypes)} hits`)
	end
	if filter.tracks then
		table.insert(out, `with {list(filter.tracks)}`)
	end
	if filter.contexts then
		table.insert(out, contextPhrase(filter.contexts))
	end
	if filter.delivery then
		local names: { string } = {}
		for _, delivery in ipairs(filter.delivery) do
			table.insert(names, DELIVERY[delivery] or delivery)
		end
		table.insert(out, `on {list(names)}`)
	end
	if filter.comboStep == "final" then
		table.insert(out, "on a combo's last step")
	elseif type(filter.comboStep) == "number" then
		table.insert(out, `on combo step {filter.comboStep}`)
	end
	if filter.crit then
		table.insert(out, "on a crit")
	end
	if filter.targetHas then
		table.insert(out, `against {statusName(filter.targetHas)}ed targets`)
	end
	if filter.targetStacks then
		table.insert(out, `against targets with {filter.targetStacks.atLeast}+ {statusName(filter.targetStacks.status)}`)
	end
	if filter.minDistance then
		table.insert(out, `beyond {number(filter.minDistance)} studs`)
	end
	if filter.infusion then
		table.insert(out, `while infused with {filter.infusion}`)
	end
	return out
end

local function sentence(main: string, filter: Filter?, skipTypes: boolean?): string
	local phrases = filterPhrases(filter, skipTypes)
	local text = if #phrases > 0 then `{main} {table.concat(phrases, ", ")}` else main
	return string.upper(string.sub(text, 1, 1)) .. string.sub(text, 2)
end

local function typesPrefix(filter: Filter?): string
	return if filter and filter.damageTypes then `{list(filter.damageTypes)} ` else ""
end

-- One effect, its growing magnitudes multiplied by `scale`.
function EffectText.describe(effect: Effect, scale: number): string
	local kind = effect.kind
	local when = effect.when
	if kind == "damage" then
		if effect.perComboStep then
			return sentence(`+{percent(effect.perComboStep * scale)} damage for each combo step before`, when)
		end
		return sentence(`+{percent((effect.increased or 0) * scale)} {typesPrefix(when)}damage`, when, true)
	elseif kind == "cost" then
		if effect.reduced then
			return sentence(`{effect.resource} costs {percent(effect.reduced * scale)} less`, when)
		end
		return sentence(`{effect.resource} costs {percent((effect.increased or 0) * scale)} more`, when)
	elseif kind == "critChance" then
		return sentence(`+{number((effect.value or 0) * scale)}% crit chance`, when)
	elseif kind == "critDamage" then
		return sentence(`+{percent((effect.increased or 0) * scale)} {typesPrefix(when)}crit damage`, when, true)
	elseif kind == "area" then
		return sentence(`+{percent((effect.increased or 0) * scale)} area of effect`, when)
	elseif kind == "reach" then
		return sentence(`+{percent((effect.increased or 0) * scale)} reach`, when)
	elseif kind == "projectileSpeed" then
		return sentence(`+{percent((effect.increased or 0) * scale)} projectile speed`, when)
	elseif kind == "moveSpeed" then
		local after = if effect.afterUse then ` for {seconds(effect.window or 0)} after an attack` else ""
		return sentence(`+{percent((effect.increased or 0) * scale)} move speed{after}`, when)
	elseif kind == "stagger" or kind == "knockback" then
		if effect.taken then
			local amount = effect.taken * scale
			return sentence(`{percent(math.abs(amount))} {if amount < 0 then "less" else "more"} {kind} taken`, when)
		end
		return sentence(`+{percent((effect.dealt or 0) * scale)} {kind} dealt`, when)
	elseif kind == "stat" then
		local value = (effect.value or 0) * scale
		if effect.mode == "percent" then
			return sentence(`+{percent(value)} {spaced(effect.stat)}`, when)
		end
		return sentence(`+{number(value)} {spaced(effect.stat)}`, when)
	elseif kind == "resistance" then
		return sentence(`+{number((effect.value or 0) * scale)} {effect.element} resistance`, when)
	elseif kind == "restore" then
		return sentence(`Restores {number((effect.amount or 0) * scale)} {effect.resource}`, when)
	elseif kind == "onHit" then
		local status = statusName(effect.status)
		local chance = effect.chance or 1
		local main = if chance >= 1 then `Hits inflict {status}` else `{percent(chance)} chance to inflict {status}`
		if effect.fromDamage and effect.fromDamage.damagePerTick then
			main ..= `, dealing {percent(effect.fromDamage.damagePerTick * scale)} of the hit each tick`
		end
		if effect.params and effect.params.duration then
			main ..= ` for {seconds(effect.params.duration)}`
		end
		if effect.cooldown then
			main ..= ` (once every {seconds(effect.cooldown)} per target)`
		end
		return sentence(main, when)
	elseif kind == "onKill" then
		if effect.action == "explode" then
			local main = `Kills explode for {percent((effect.maxHealthShare or 0) * scale)} of the target's health as {effect.element}`
			if effect.status then
				main ..= `, inflicting {statusName(effect.status)}`
			end
			return sentence(main, when)
		end
		local count = effect.count or 1
		return sentence(
			`Kills spread {statusName(effect.status)} to {count} nearby {if count == 1 then "enemy" else "enemies"}`,
			when
		)
	elseif kind == "statusBoost" then
		local status = statusName(effect.status)
		local parts: { string } = {}
		if effect.duration then
			table.insert(parts, `{status} lasts {percent(effect.duration * scale)} longer`)
		end
		if effect.potency then
			table.insert(parts, `{status} is {percent(effect.potency * scale)} stronger`)
		end
		if effect.extraStacks then
			table.insert(parts, `{status} stacks {effect.extraStacks} higher`)
		end
		return sentence(table.concat(parts, "; "), when)
	elseif kind == "field" then
		if effect.damageShare then
			return sentence(
				`Leaves a field dealing {percent(effect.damageShare * scale)} of the hit over {seconds(effect.duration or 0)}`,
				when
			)
		end
		return sentence(`Leaves a {statusName(effect.status or "")} field for {seconds(effect.duration or 0)}`, when)
	end
	return sentence(kind, when)
end

return EffectText
