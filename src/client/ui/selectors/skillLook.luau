--!strict
-- What a skill looks like wherever it is drawn (the HUD's bar, the Loadout): mastery art where it
-- exists, else a line glyph. The skill specs' own `icon` is one placeholder shared by every skill,
-- so it cannot tell them apart.
--
-- The basic attack takes the look of the form it plays, so the bar changes with the form.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientSpec = require(ReplicatedStorage.Shared.skills.ClientSpec)
local BasicAttackForm = require(ReplicatedStorage.Shared.skills.BasicAttackForm)
local MasteryTracks = require(ReplicatedStorage.Shared.progression.MasteryTracks)
local ItemTypes = require(ReplicatedStorage.Shared.items.ItemTypes)

export type Look = {
	-- MasteryArt key, when the art exists; the glyph otherwise.
	art: string?,
	glyph: string,
}

-- Glyphs for skills without art of their own (ItemGlyphs).
local SKILL_GLYPH: { [string]: string } = {
	ManaBall = "orb",
	CascadingManaBalls = "orbs",
	Dash = "dash",
	DodgeRoll = "roll",
	TripleStrike = "sword",
	Punch = "fist",
}

local BASIC_ATTACK = "BasicAttack"

local function lookOf(skill: string, combat: ItemTypes.CombatLoadoutSnapshot?): Look
	if skill == BASIC_ATTACK then
		local form = BasicAttackForm.resolve(combat)
		local main = combat and combat.main
		return { art = form.shapeNode, glyph = if main then main.weaponClass else "fist" }
	end
	local spec = ClientSpec[skill]
	local track = spec and spec.mastery and MasteryTracks.get(spec.mastery.track)
	return { art = nil, glyph = SKILL_GLYPH[skill] or (if track then track.glyph else "box") }
end

return lookOf
