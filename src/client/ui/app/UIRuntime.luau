--!strict
-- Drives world panels: keeps a host per registered panel and tells each whether it should be visible.
--
-- Components pull their own state (R16), so all that is left to drive from outside is visibility.
--
-- Most panels' visibility is a function of menu state, so the menu store drives re-evaluation. A
-- panel that depends on something else -- nearby loot, a controller -- supplies a `watch` that
-- re-triggers evaluation; its `isVisible` then reads that source directly and ignores the state
-- argument. This is why visibility is not simply a React render decision: the *surface* has to exist
-- or not, and that is imperative.
--
-- Hosts are created lazily on first show and then kept alive. Destroying on close would fight the
-- fade-out, which needs the surface to outlive the animation. Once a hide has finished fading, the
-- host drops its React subtree while the surface and root persist.

local MenuOrchestrator = require(script.Parent.Parent.menu.MenuOrchestrator)
local MenuRigRuntime = require(script.Parent.Parent.menu.MenuRigRuntime)
local PanelRegistry = require(script.Parent.PanelRegistry)
local PanelHost = require(script.Parent.PanelHost)

local React = require(game:GetService("ReplicatedStorage").Packages.React)

local UIRuntime = {}

local hosts: { [string]: PanelHost.PanelHostType } = {}
-- Live world-scale changes from the stage tuner, kept so a host created after the change gets it too.
local scaleOverrides: { [string]: number } = {}
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
		local scale = scaleOverrides[entry.id]
		if scale then
			created:setScale(scale)
		end
	end

	-- Before visibility, so a panel fading in is already at its new anchor.
	local followTarget = entry.followTarget
	if followTarget then
		host:setFollowTarget(followTarget())
	end

	-- `visible` reaches the component so a panel on its way out can hold its last state through the
	-- fade (the host keeps rendering until the fade completes).
	--
	-- A render error must not strand the host: it is hidden rather than left half-shown, and the next
	-- state change tries again. Unguarded, one throw left the panel looking like it had stopped
	-- existing rather than like an error.
	local ok, err = pcall(function()
		host:present(React.createElement(entry.component, { visible = visible }), visible)
	end)
	if not ok then
		warn(`[UIRuntime] {entry.id} render failed: {err}`)
		host:setVisible(false)
	end
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

	-- The stage spaces side panels by width, including ones never shown yet, so it needs every size up
	-- front rather than reading them off parts that may not exist.
	local rig = MenuRigRuntime.get()
	for _, entry in ipairs(PanelRegistry.list()) do
		local scale = entry.surface.scale or 1
		rig:setPanelSize(entry.id, entry.surface.width * scale, entry.surface.height * scale)
	end

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

-- Resizes a panel in the world at runtime: its host if it exists, and the size the menu stage spaces
-- side panels by. For live tuning; the authored scale lives on the registry entry.
function UIRuntime.setPanelScale(id: string, scale: number)
	local entry = PanelRegistry.get(id)
	if not entry then
		return
	end
	scaleOverrides[id] = scale
	MenuRigRuntime.get():setPanelSize(id, entry.surface.width * scale, entry.surface.height * scale)
	local host = hosts[id]
	if host then
		host:setScale(scale)
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
