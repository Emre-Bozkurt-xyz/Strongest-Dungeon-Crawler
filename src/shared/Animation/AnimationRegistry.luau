--!strict
-- Every animation clip, reachable by its full name "<owner>/<clip>".
--
-- Clips are declared in their owner's own module under `animations` -- an attack profile owns its
-- moveset, a skill spec owns the skill's clips -- so a clip lives, changes and is deleted alongside
-- the thing that plays it, and its ID shows up in that owner's diff. This module only gathers them.
-- References always use the full name, including inside the owner, so a key means the same thing
-- wherever it appears: in a profile step, a skill spec, or an item's animationOverrides.
--
-- Character specs (Characters/) keep their raw IDs for now: NPC playback reads them on the server
-- and never goes through a key.

local AnimationTypes = require(script.Parent.AnimationTypes)
local BasicAttackProfileRegistry = require(script.Parent.Parent.skills.BasicAttackProfileRegistry)
local ClientSpec = require(script.Parent.Parent.skills.ClientSpec)

export type Clip = {
	key: string,
	owner: string,
	-- nil while the clip is declared but not published.
	id: string?,
}

local AnimationRegistry = {}

local SEPARATOR = "/"

local clips: { [string]: Clip } = {}
local ownersSeen: { [string]: string } = {}

local function register(owner: string, set: AnimationTypes.ClipSet, source: string)
	assert(
		ownersSeen[owner] == nil,
		`[AnimationRegistry] owner '{owner}' declared by both {ownersSeen[owner]} and {source}`
	)
	ownersSeen[owner] = source
	for name, id in set do
		assert(
			not string.find(name, SEPARATOR, 1, true),
			`[AnimationRegistry] clip name '{name}' in {source} must not contain '{SEPARATOR}'`
		)
		local key = owner .. SEPARATOR .. name
		clips[key] = {
			key = key,
			owner = owner,
			id = if type(id) == "string" and id ~= "" then id else nil,
		}
	end
end

for _, profile in BasicAttackProfileRegistry.list() do
	if profile.animations then
		register(profile.id, profile.animations, `profile {profile.id}`)
	end
end

for skillName, spec in ClientSpec do
	if spec.animations then
		register(skillName, spec.animations, `skill spec {skillName}`)
	end
end

-- A reference to an undeclared clip is a typo or a clip that was never added to its owner; either
-- way it would play nothing, so it is reported once at load rather than on every swing.
local function checkReference(key: any, where: string)
	if type(key) ~= "string" or key == "" then
		return
	end
	if clips[key] == nil then
		warn(`[AnimationRegistry] {where} plays '{key}', which no owner declares`)
	end
end

local function checkAnimSpec(anim: any, where: string)
	if type(anim) ~= "table" then
		return
	end
	for _, field in { "start", "finish" } do
		local spec = anim[field]
		checkReference(if type(spec) == "table" then spec.key else spec, where)
	end
	if type(anim.comboSteps) == "table" then
		for _, step in anim.comboSteps do
			checkReference(step.key, where)
		end
	end
	checkReference(anim.comboIdle, where)
end

for _, profile in BasicAttackProfileRegistry.list() do
	local where = `profile {profile.id}`
	for _, step in profile.steps do
		checkReference(step.animation, where)
	end
	checkReference(profile.idleAnimation, where)
end

for skillName, spec in ClientSpec do
	local where = `skill spec {skillName}`
	checkAnimSpec(spec.anim, where)
	if spec.directional then
		for _, visual in spec.directional do
			checkAnimSpec(visual.anim, where)
		end
	end
end

function AnimationRegistry.get(key: string): Clip?
	return clips[key]
end

function AnimationRegistry.list(): { Clip }
	local out = {}
	for _, clip in clips do
		table.insert(out, clip)
	end
	table.sort(out, function(a, b)
		return a.key < b.key
	end)
	return out
end

return AnimationRegistry
