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
}

return ClientSpec
