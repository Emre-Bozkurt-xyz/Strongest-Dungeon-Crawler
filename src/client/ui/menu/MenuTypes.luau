--!strict
-- Menu state shape, shared by the store, its reducer, the orchestrator and PanelRegistry predicates.

export type MenuView = "system" | "inventory" | "equipment" | "loadout"
-- "loadout" inspects a skill or the basic attack's form rather than an item.
export type InspectSource = "inventory" | "equipment" | "loadout"

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
