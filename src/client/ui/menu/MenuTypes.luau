--!strict
-- Menu state shape, shared by the store, its reducer, the orchestrator and PanelRegistry predicates.

export type MenuView = "system" | "inventory" | "equipment" | "loadout"
export type InspectSource = "inventory" | "equipment"

-- A side panel the player shows or hides rather than one an inspect opens, keyed in `contextPanels`.
-- Unset counts as shown: the Loadout's skills are open until the player hides them.
export type ContextPanel = "LoadoutSkillsPanel"

export type MenuModalState = {
	open: boolean,
	view: MenuView,
	primaryPanelId: string,
	sidePanelIds: { string },
}

export type InspectState = {
	source: InspectSource,
	payload: any,
}

export type MenuState = {
	modal: MenuModalState,
	contextPanels: { [string]: boolean },
	transientQueue: { any },
	inspect: InspectState?,
}

export type MenuAction = {
	type: string,
	view: MenuView?,
	source: InspectSource?,
	payload: any?,
	panelId: string?,
	visible: boolean?,
	transient: any?,
}

return {}
