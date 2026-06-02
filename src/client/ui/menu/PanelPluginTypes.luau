--!strict

export type MenuTier = "modal" | "context" | "transient"
export type MenuView = "system" | "inventory" | "equipment"
export type InspectSource = "inventory" | "equipment"

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

export type PanelPluginHost = {
	getState: () -> MenuState,
	dispatch: (action: MenuAction) -> (),
	publish: (event: any) -> (),
}

export type PanelPlugin = {
	id: string,
	tier: MenuTier,
	mount: (host: PanelPluginHost) -> (),
	onStateChanged: (prev: MenuState, next: MenuState) -> (),
	onData: (event: any) -> (),
	unmount: () -> (),
}

return {}
