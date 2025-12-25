--!strict
-- OverheadHealthService: registers overhead HP bars with WorldGUIManager, following entity HRP

-- local Players = game:GetService("Players") -- not used currently
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local EntityRevealStore = require(script.Parent.EntityRevealStore)
local WorldGUIManager = require(script.Parent.WorldGUIManager)
local OverheadHealthBarController = require(script.Parent.ui.controllers.OverheadHealthBarController)
local ClientRegistrar = require(script.Parent.ClientRegistrar)

-- Now driven by EntityRevealStore

local Y_OFFSET = 3.0 -- studs above the entity position
-- Presence-based grace windows to avoid churn
local HIDE_AFTER = 1.0 -- seconds with no presence before fade-out (kept alive)
local DESTROY_AFTER = 4.0 -- seconds with no presence before destroy
local OFFSCREEN_GRACE = 1 -- seconds off-screen before auto-hide (still kept alive)
local FADE_TIME = 0.2 -- controller fade duration for cleanup

local OverheadHealthService = {}

type BarRecord = {
	id: string,
	part: BasePart,
	anchor: BasePart?,
	lastSeen: number,
	controller: any?,
	isHidden: boolean?,
	lastVisible: number?,
}

local _bars: { [string]: BarRecord } = {}
local _isStarted: boolean = false
local _template: BasePart? = nil

local function _panelName(id: string): string
	return "OverheadHPBar_" .. id
end

local function _ensureTemplate(): BasePart?
	if _template and _template.Parent then
		return _template
	end
	local assets = ReplicatedStorage:WaitForChild("Assets")
	local worldUI = assets:WaitForChild("WorldUI")
	local tpl = worldUI:WaitForChild("OverheadHPBar")
	_template = tpl :: BasePart
	return _template
end

local function _spawnBar(id: string, worldPos: Vector3): BarRecord?
	local tpl = _ensureTemplate()
	if not tpl then
		return nil
	end
	local part = (tpl:Clone()) :: BasePart
	part.Name = "HPBar_" .. id
	part.Parent = Workspace
	part.Anchored = true
	local pos = worldPos + Vector3.new(0, Y_OFFSET, 0)
	part.CFrame = CFrame.new(pos)
	local now = os.clock()
	local rec: BarRecord = { id = id, part = part, anchor = nil, lastSeen = now, isHidden = false, lastVisible = now }
	_bars[id] = rec

	-- Register panel with WorldGUIManager in target-follow mode (we will set anchor shortly)
	local wgm = WorldGUIManager.getInstance()
	wgm:registerPanel({
		name = _panelName(id),
		part = part,
		faceCamera = true,
		followMode = "target",
		followTarget = nil,
		lerpSpeed = 36, -- fast follow for healthbars
		offset = Vector3.new(0, Y_OFFSET, 0),
	})
	-- Attach controller and fade in
	rec.controller = OverheadHealthBarController.new(part)
	if rec.controller then
		rec.controller:show()
	end
	return rec
end

local function _findAnchorForEntity(id: string): BasePart?
	-- Use ClientRegistrar to efficiently find entity, then get HumanoidRootPart
	local entity = ClientRegistrar.getEntity(id)
	if not entity then
		return nil
	end

	-- Entity might be the model itself or a part within it
	local model: Instance? = entity
	if not entity:IsA("Model") then
		model = entity.Parent
	end

	if model and model:IsA("Model") then
		local hrp = model:FindFirstChild("HumanoidRootPart")
		if hrp and hrp:IsA("BasePart") then
			return hrp
		end
	end

	return nil
end

local function _destroyBar(id: string)
	local rec = _bars[id]
	if not rec then
		return
	end
	_bars[id] = nil
	-- Unregister the panel from WorldGUIManager before destroying the part
	local wgm = WorldGUIManager.getInstance()
	wgm:unregisterPanel(_panelName(id))
	if rec.controller then
		pcall(function()
			rec.controller:hide()
			rec.controller:destroy()
		end)
	end
	-- allow fade to finish before destroying the part
	task.delay(FADE_TIME + 0.05, function()
		pcall(function()
			rec.part:Destroy()
		end)
	end)
end

local function _onDelta(payload: any)
	if not _isStarted then
		return
	end
	if not payload or payload.type ~= "presence" then
		return
	end
	local seen: { [string]: boolean } = {}
	local now = os.clock()
	for _, item in ipairs(payload.items :: { any }) do
		local id = item.id
		local pos = item.pos :: Vector3
		seen[id] = true
		local hasPerc = item.hpPerc ~= nil
		local hasHp = item.hp ~= nil
		if not hasPerc and not hasHp then
			-- No reveal -> tear down if exists
			if _bars[id] then
				_destroyBar(id)
			end
			continue
		end

		local rec = _bars[id]
		if not rec then
			local spawned = _spawnBar(id, pos)
			if spawned then
				rec = spawned
			end
		end
		if rec then
			-- Update via controller
			pcall(function()
				local ctrl = rec.controller
				if ctrl then
					if hasHp then
						local hp = item.hp :: any
						ctrl:setCurrentMax(hp.current, hp.max)
					elseif hasPerc then
						ctrl:setPercent(item.hpPerc :: number)
					end
					ctrl:setName(item.name :: string)
				end
			end)
			-- Update follow anchor to entity HRP if possible
			if not rec.anchor then
				-- Use ClientRegistrar for efficient entityId lookup
				local hrp = _findAnchorForEntity(id)
				if hrp then
					rec.anchor = hrp
					local wgm = WorldGUIManager.getInstance()
					wgm:setPanelFollowTarget(_panelName(id), hrp)
				else
					-- Fallback: snap to last reported position via manual placement until we resolve anchor
					rec.part.CFrame = CFrame.lookAt(
						pos + Vector3.new(0, Y_OFFSET, 0),
						Workspace.CurrentCamera and Workspace.CurrentCamera.CFrame.Position
							or (pos + Vector3.new(0, 0, -1))
					)
				end
			end
			rec.lastSeen = now

			-- On-screen visibility tracking to avoid churn
			local cam = Workspace.CurrentCamera
			local anchorPos = (rec.anchor and rec.anchor.Position) or pos
			local barPos = anchorPos + Vector3.new(0, Y_OFFSET, 0)
			local isOnScreen = false
			if cam then
				local vp, onScreen = cam:WorldToViewportPoint(barPos)
				if onScreen and vp.Z > 0 then
					isOnScreen = true
				end
			end
			if isOnScreen then
				rec.lastVisible = now
				if rec.isHidden and rec.controller then
					pcall(function()
						rec.controller:show()
					end)
					rec.isHidden = false
				end
			end
		end
	end

	-- Prune/hide bars based on presence and visibility grace windows
	for id, rec in pairs(_bars) do
		local noPresenceFor = now - rec.lastSeen
		local notVisibleFor = now - (rec.lastVisible or rec.lastSeen)
		-- Presence-based fade and destroy
		if not seen[id] then
			if noPresenceFor > DESTROY_AFTER then
				_destroyBar(id)
			elseif noPresenceFor > HIDE_AFTER then
				if not rec.isHidden and rec.controller then
					pcall(function()
						rec.controller:hide()
					end)
					rec.isHidden = true
				end
			end
		end
		-- Off-screen based hide (kept alive)
		if seen[id] and notVisibleFor > OFFSCREEN_GRACE then
			if not rec.isHidden and rec.controller then
				pcall(function()
					rec.controller:hide()
				end)
				rec.isHidden = true
			end
		end
	end

	-- Density-based alpha damping: keep nearest 6 full alpha, fade others toward 0.3
	local cam = Workspace.CurrentCamera
	if cam then
		local camPos = cam.CFrame.Position
		local active: { { id: string, dist: number, rec: BarRecord } } = {}
		for id, rec in pairs(_bars) do
			if rec and rec.controller and not rec.isHidden then
				local p = rec.part.CFrame.Position
				local d = (p - camPos).Magnitude
				table.insert(active, { id = id, dist = d, rec = rec })
			end
		end
		table.sort(active, function(a, b)
			return a.dist < b.dist
		end)
		local hardCap = 6
		for i, entry in ipairs(active) do
			local alpha = 1.0
			if i > hardCap then
				local over = i - hardCap
				alpha = math.max(0.3, 1.0 - over * 0.1)
			end
			pcall(function()
				if entry.rec.controller then
					entry.rec.controller:setAlphaMultiplier(alpha)
				end
			end)
		end
	end
end

function OverheadHealthService.start()
	if _isStarted then
		return
	end
	_isStarted = true
	EntityRevealStore.start()
	EntityRevealStore.onPresence(_onDelta)
end

function OverheadHealthService.stop()
	if not _isStarted then
		return
	end
	_isStarted = false
	for id, _ in pairs(_bars) do
		_destroyBar(id)
	end
end

return OverheadHealthService
