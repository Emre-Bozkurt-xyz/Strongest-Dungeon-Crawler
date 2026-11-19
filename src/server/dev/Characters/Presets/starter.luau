--!strict
-- What a new player has once the dev session has set them up (Dev.onSessionStart): the shared
-- StarterKit's skills, starting items, attribute point and AttackSpeed base.
local StarterKit = require(script.Parent.Parent.Parent.StarterKit)

return {
	attributes = StarterKit.attributes,
	skills = StarterKit.skills,
	bag = StarterKit.items,
	stats = StarterKit.stats,
}
