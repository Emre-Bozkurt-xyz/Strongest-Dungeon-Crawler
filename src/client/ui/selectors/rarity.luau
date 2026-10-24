--!strict
-- Rarity tints, shared by every surface that shows an item.
--
-- Not sourced from the theme (Guardrail 3 is about UI chrome, not item data): rarity is a fixed
-- four-value item property, and a magic item should read as magic whichever theme is active.

local Rarity = {}

local TINTS: { [string]: Color3 } = {
	normal = Color3.fromRGB(190, 190, 190),
	magic = Color3.fromRGB(120, 160, 255),
	rare = Color3.fromRGB(240, 210, 110),
	unique = Color3.fromRGB(230, 140, 70),
}

function Rarity.tint(rarity: string?): Color3?
	if not rarity then
		return nil
	end
	return TINTS[rarity]
end

return Rarity
