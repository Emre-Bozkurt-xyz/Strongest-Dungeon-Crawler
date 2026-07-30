--!strict
-- Client-facing visual spec per skill (animations/FX/SFX keys)
-- Keys must match assets under ReplicatedStorage/Assets

local SpecFolder = script.Parent.Specs
local Types = require(script.Parent.SkillSpecTypes)

local ClientSpec: Types.SkillSpecMap = {
	Punch = require(SpecFolder.Punch),
	TripleStrike = require(SpecFolder.TripleStrike),
	Dash = require(SpecFolder.Dash),
	DodgeRoll = require(SpecFolder.DodgeRoll),
	ManaBall = require(SpecFolder.ManaBall),
	CascadingManaBalls = require(SpecFolder.CascadingManaBalls),
	-- ClientSpec is a manual map, not autoloaded (unlike SkillsData/ on the server) -- a new skill
	-- must be added here explicitly or the client warns "no client spec for skill" and the keybind
	-- silently does nothing (see trap 2 in the Phase B handoff brief).
	BasicAttack = require(SpecFolder.BasicAttack),
}

return ClientSpec
