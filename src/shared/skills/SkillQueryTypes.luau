--!strict

-- Shared types for skill stat/behavior queries used by both server and client.

export type SkillQueryContext = {
	entityId: string,
	skillId: string,
	event: string, -- e.g. "resolveSkillCost" | "resolveSkillTempo" | ...
	tags: { string }?,
	step: number?,
	metadata: { [string]: any }?,
	base: { [string]: any },
}

export type SkillQueryResult = {
	values: { [string]: any },
	log: { string }?,
}

export type SkillModifier = {
	id: string,
	priority: number,
	matches: (ctx: SkillQueryContext) -> boolean,
	apply: (ctx: SkillQueryContext, result: SkillQueryResult) -> (),
}

return {
	SkillQueryContext = nil :: any,
	SkillQueryResult = nil :: any,
	SkillModifier = nil :: any,
}
