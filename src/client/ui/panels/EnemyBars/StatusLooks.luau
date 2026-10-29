--!strict
-- How each status effect is marked under an enemy's health bar: a glyph and its colour. Keyed by
-- the server's effect id (server/StatusEffects/EffectsIndex). Glyphs and colours are placeholders.
--
-- An effect missing here still shows, as a plain orb, so a new one is never silently invisible.

export type Look = {
	glyph: string,
	color: Color3,
	-- Never shown: too brief or too constant to be worth a mark.
	hidden: boolean?,
}

local LOOKS: { [string]: Look } = {
	-- Damage over time. Burn and Chill take their element track's colour (MasteryTracks).
	Burn = { glyph = "flame", color = Color3.fromRGB(255, 120, 45) },
	Bleed = { glyph = "drop", color = Color3.fromRGB(235, 70, 80) },
	Poison = { glyph = "bubbles", color = Color3.fromRGB(150, 215, 80) },
	-- Hindrances.
	Chill = { glyph = "snowflake", color = Color3.fromRGB(120, 210, 255) },
	Freeze = { glyph = "crystal", color = Color3.fromRGB(200, 240, 255) },
	Slow = { glyph = "hourglass", color = Color3.fromRGB(175, 185, 220) },
	Sunder = { glyph = "brokenShield", color = Color3.fromRGB(230, 175, 100) },
	-- Blocking.
	stun = { glyph = "star", color = Color3.fromRGB(255, 215, 90) },
	stagger = { glyph = "daze", color = Color3.fromRGB(235, 228, 205) },
	root = { glyph = "anchor", color = Color3.fromRGB(150, 200, 155) },
	silence = { glyph = "mute", color = Color3.fromRGB(190, 150, 255) },
	-- Dodge frames: a few tenths of a second, on every roll.
	invulnerable = { glyph = "orb", color = Color3.new(1, 1, 1), hidden = true },
	-- Buffs.
	Frenzy = { glyph = "chevrons", color = Color3.fromRGB(255, 160, 95) },
}

local FALLBACK: Look = { glyph = "orb", color = Color3.fromRGB(215, 220, 230) }

local StatusLooks = {}

function StatusLooks.get(id: string): Look
	return LOOKS[id] or FALLBACK
end

return StatusLooks
