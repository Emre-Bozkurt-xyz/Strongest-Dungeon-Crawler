--!strict
-- Drives world panels: keeps a host per registered panel and tells each whether it should be visible.
--
-- Replaces PanelPluginRegistry and the per-panel plugin lifecycle (R16). A plugin's job was to push
-- state into a runtime; components pull it themselves, so all that remains is visibility.
--
-- Most panels' visibility is a function of menu state, so the menu store drives re-evaluation. A
-- panel that depends on something else -- nearby loot, a controller -- supplies a `watch` that
-- re-triggers evaluation; its `isVisible` then reads that source directly and ignores the state
-- argument. This is why visibility is not simply a React render decision: the *surface* has to exist
-- or not, and that is imperative.
--
-- Hosts are created lazily on first show and then kept alive. Destroying on close would fight the
-- fade-out, which needs the surface to outlive the animation. A hidden host renders nil, so its
-- React subtree drops while the surface and root persist.

local MenuOrchestrator = require(script.Parent.Parent.menu.MenuOrchestrator)
local PanelRegistry = require(script.Parent.PanelRegistry)
local PanelHost = require(script.Parent.PanelHost)

local React = require(game:GetService("ReplicatedStorage").Packages.React)

local UIRuntime = {}

local hosts: { [string]: PanelHost.PanelHostType } = {}
local disconnect: (() -> ())? = nil
local watchers: { () -> () } = {}
local started = false

local function applyEntry(entry: PanelRegistry.PanelEntry, state: any)
	local visible = entry.isVisible(state)
	local host = hosts[entry.id]

	if not host then
		-- Nothing to do for a panel that has never been shown; creating a surface for it would
		-- cost a part and a React root to display nothing.
		if not visible then
			return
		end
		local created
		local ok, err = pcall(function()
			created = PanelHost.new(entry)
		end)
		if not ok or not created then
			warn(`[UIRuntime] {entry.id} host creation failed: {err}`)
			return
		end
		host = created
		hosts[entry.id] = host
	end

	-- A render error must not strand the host. Visibility used to be set only after a successful
	-- render, so one throw left `_visible` false forever and the panel never faded back in -- the
	-- failure looked like "the panel stopped existing" rather than an error.
	local ok, err = pcall(function()
		(host :: any):render(if visible then React.createElement(entry.component) else nil)
	end)
	if not ok then
		warn(`[UIRuntime] {entry.id} render failed: {err}`)
	end
	;(host :: any):setVisible(visible and ok)
end

local function applyState(state: any)
	for _, entry in ipairs(PanelRegistry.list()) do
		applyEntry(entry, state)
	end
end

function UIRuntime.start()
	if started then
		return
	end
	started = true

	applyState(MenuOrchestrator.getState())
	disconnect = MenuOrchestrator.onChanged(function(_prev, next)
		applyState(next)
	end)

	for _, entry in ipairs(PanelRegistry.list()) do
		local watch = entry.watch
		if watch then
			-- Only this entry is re-evaluated: an unrelated panel's source firing should not walk
			-- the whole registry.
			table.insert(watchers, watch(function()
				applyEntry(entry, MenuOrchestrator.getState())
			end))
		end
	end
end

function UIRuntime.stop()
	if not started then
		return
	end
	started = false

	if disconnect then
		disconnect()
		disconnect = nil
	end
	for _, unwatch in ipairs(watchers) do
		unwatch()
	end
	table.clear(watchers)
	for id, host in pairs(hosts) do
		host:destroy()
		hosts[id] = nil
	end
end

return UIRuntime
