--!strict
-- The shape of a character spec: a declarative description of a player's character that
-- Characters.apply turns into a stand-in save (plus the session-only parts no save holds) and
-- puts on a live player.
--
-- Every field is optional. What a spec leaves out comes from a brand-new save
-- (PlayerDataSchema.template): level 1, default attributes and points, no mastery, the default slot
-- sets, an empty bag, nothing owned.
--
-- `extends` names another preset to start from. The parent is resolved first (it may extend in
-- turn), then this spec is laid over it:
--   - a map (a table with only string keys: `attributes`, `mastery`, `equipment`, `stats`, ...)
--     merges key by key, recursively, so `equipment = { Main = ... }` keeps the parent's Body;
--   - a list, an item, or any table with positional entries (`skills`, `bar`, `bag`,
--     `{ "iron_sword", rarity = "magic" }`) replaces the parent's value whole, and so does an empty
--     table, which reads as "none";
--   - `false` removes what the parent set for that key (`equipment = { Secondary = false }`);
--   - any other value replaces.
--
-- Items (`ItemSpec`) are made through the inventory's own creation path, so anything not stated is
-- rolled the way a drop would be (rarity, affixes, base rolls). `meta` is the exact item instance
-- meta, as `Characters.capture` writes it, and reproduces an item exactly; `rarity`, `itemLevel` and
-- `affixes` are the authoring shorthands, laid over `meta` when both are given.

export type AffixSpec = string | {
	-- [1]: affix id ("fury", "of_vigor", ...).
	[number]: string,
	-- Affix tier; a weighted tier the item qualifies for when left out.
	tier: number?,
}

export type ItemSpec = string | {
	-- [1]: item id ("iron_sword"). [2]: stack count, for the bag only (also `count`).
	[number]: any,
	count: number?,
	-- "normal" | "magic" | "rare" | "unique".
	rarity: string?,
	itemLevel: number?,
	-- Exactly these affixes, rolled in their tier's ranges; none rolled beyond them.
	affixes: { AffixSpec }?,
	-- Raw instance meta (affixes with their rolled values, baseModifiers, rarity, displayName...).
	meta: { [string]: any }?,
	-- Bag only: the inventory slot (1-based). Unplaced items fill the first free slots in order.
	slot: number?,
}

-- Branch XP as a number; or the least XP that reaches a rank (`{ rank = 2 }`); or "mastered", the
-- branch's cap. Ranks: trunk 0-2, branches 1-4 (a branch's rank 1 opens from the trunk, so its XP is
-- 0 and the trunk needs MasteryXP.BRANCH_ENTRY).
export type BranchSpec = number | string | { rank: number }

export type Spec = {
	-- Preset to start from (see the merge rules above).
	extends: string?,
	-- Character level, converted to total XP through CharacterXP. Give this or `xp`, not both.
	level: number?,
	-- Total character XP.
	xp: number?,
	-- Base value per attribute ("Strength", "Defense", "Dexterity", "Intelligence", "Perception"),
	-- and `unspent` points. Unnamed attributes stay at their default; leaving out `unspent` keeps the
	-- default point pool (AttributesConfig.DefaultAttributePoints).
	attributes: { [string]: number }?,
	-- Track id ("Blade", "Blunt", "Magic", "Ranged", "Fire", "Frost") -> branch ("trunk", "a", "b")
	-- -> BranchSpec.
	mastery: { [string]: { [string]: BranchSpec } }?,
	-- Attuned track ids, no more than the level's slots (Attunement.slotsFor).
	attuned: { string }?,
	-- Skills the character owns this session (SkillsConfig names). Session-only: no save holds them.
	skills: { string }?,
	-- Skill slot sets, each a list of up to LoadoutTypes.SLOTS_PER_SET skill names ("" for empty).
	-- A skill not in `skills` keeps its slot but cannot be cast, as in a real save. Left out: the
	-- default sets of a new save.
	bar: { { string } }?,
	-- The set in use, 1-based.
	activeSet: number?,
	-- Equip slot ("Main", "Secondary", "Head", "Neck", "Body", "Hands", "Waist", "Feet", "Ring1",
	-- "Ring2") -> item. Equipped as a save would restore it: an item whose requirements the character
	-- does not meet stays equipped but inactive.
	equipment: { [string]: ItemSpec | false }?,
	-- Items in the inventory, in order.
	bag: { ItemSpec }?,
	-- Inventory slot count (30 in a new save).
	capacity: number?,
	-- Selected basic attack shape (profile id) per weapon class key ("unarmed", "sword", "wand"...).
	-- Must be unlocked by the mastery above, or granted by the equipped main-hand weapon.
	shapes: { [string]: string }?,
	-- Selected infusion node id ("fire.fire_1"...), or "" for none. Must be unlocked.
	infusion: string?,
	-- Chosen selectable passive node ids, unlocked, in effect, and within the level's slots
	-- (PassivePool.slotsFor).
	passives: { string }?,
	-- Pool ("Health", "Mana", "Stamina", "ManaShield") -> starting value: a fraction of the maximum
	-- when <= 1, an absolute amount above that. Pools not named start full.
	pools: { [string]: number }?,
	-- Base value overrides per stat (StatTypes names: "AttackSpeed", "Armor", "Health"...).
	-- Session-only; Characters.restore puts back what each stat had before.
	stats: { [string]: number }?,
}

return {}
