--!strict
-- Movement Component: Handles NPC pathfinding, speed, and movement states
-- Integrates with Roblox PathfindingService for navigation

local PathfindingService = game:GetService("PathfindingService")
local RunService = game:GetService("RunService")

local NPCManager = require(script.Parent.Parent.NPCManager)

local Movement = {}
Movement.__index = Movement

-- Static registry for Movement components
local _Registry: { [Model]: boolean } = {}
local function _register(model: Model)
	_Registry[model] = true
	model.Destroying:Connect(function()
		_Registry[model] = nil
	end)
end

export type MovementConfig = {
	walkSpeed: number?,
	runSpeed: number?,
	patrolRadius: number?,
	jumpHeight: number?,
	canJump: boolean?,
}

export type MovementState = "idle" | "walking" | "running" | "patrolling" | "chasing" | "stuck"

-- Create a Movement component for an NPC
function Movement.new(npcModel: Model, config: MovementConfig): any
	local component = NPCManager.addComponent(npcModel, "Movement")
	
	-- Set up movement attributes
	npcModel:SetAttribute("WalkSpeed", config.walkSpeed or 8)
	npcModel:SetAttribute("RunSpeed", config.runSpeed or 16)
	npcModel:SetAttribute("PatrolRadius", config.patrolRadius or 10)
	npcModel:SetAttribute("JumpHeight", config.jumpHeight or 7.2)
	npcModel:SetAttribute("CanJump", config.canJump ~= false)
	
	-- Movement state tracking
	npcModel:SetAttribute("MovementState", "idle")
	component:SetAttribute("targetPosition", Vector3.new(0, 0, 0))
	component:SetAttribute("patrolCenter", npcModel.PrimaryPart and npcModel.PrimaryPart.Position or Vector3.new(0, 0, 0))
	component:SetAttribute("lastPathUpdate", 0)
	component:SetAttribute("stuckCheckTime", 0)
	component:SetAttribute("lastPosition", Vector3.new(0, 0, 0))
	
	local self = setmetatable({
		model = npcModel,
		component = component,
		currentPath = nil,
		pathIndex = 1,
	}, Movement)
	
	-- Set up Humanoid movement properties
	local humanoid = npcModel:FindFirstChild("Humanoid") :: Humanoid?
	if humanoid then
		humanoid.WalkSpeed = config.walkSpeed or 8
		humanoid.JumpHeight = config.jumpHeight or 7.2
	end
	
	_register(npcModel)
	return self
end

-- Get Movement component from an NPC model
function Movement.get(npcModel: Model): any?
	if not NPCManager.hasComponent(npcModel, "Movement") then
		return nil
	end
	
	local component = NPCManager.getComponent(npcModel, "Movement")
	if not component then return nil end
	
	return setmetatable({
		model = npcModel,
		component = component,
		currentPath = nil,
		pathIndex = 1,
	}, Movement)
end

-- Get current movement state
function Movement:getState(): MovementState
	return self.model:GetAttribute("MovementState") or "idle"
end

-- Set movement state
function Movement:setState(state: MovementState)
	self.model:SetAttribute("MovementState", state)
end

-- Get current position
function Movement:getPosition(): Vector3
	local humanoidRootPart = self.model:FindFirstChild("HumanoidRootPart") :: BasePart?
	return humanoidRootPart and humanoidRootPart.Position or Vector3.new(0, 0, 0)
end

-- Set walk speed
function Movement:setWalkSpeed(speed: number)
	self.model:SetAttribute("WalkSpeed", speed)
	local humanoid = self.model:FindFirstChild("Humanoid") :: Humanoid?
	if humanoid then
		humanoid.WalkSpeed = speed
	end
end

-- Set run speed (used during chasing/combat)
function Movement:setRunSpeed(speed: number)
	self.model:SetAttribute("RunSpeed", speed)
end

-- Switch to run speed
function Movement:enableRunning()
	local runSpeed = self.model:GetAttribute("RunSpeed") or 16
	local humanoid = self.model:FindFirstChild("Humanoid") :: Humanoid?
	if humanoid then
		humanoid.WalkSpeed = runSpeed
	end
end

-- Switch to walk speed
function Movement:enableWalking()
	local walkSpeed = self.model:GetAttribute("WalkSpeed") or 8
	local humanoid = self.model:FindFirstChild("Humanoid") :: Humanoid?
	if humanoid then
		humanoid.WalkSpeed = walkSpeed
	end
end

-- Move to a specific position
function Movement:moveTo(targetPosition: Vector3)
	local humanoid = self.model:FindFirstChild("Humanoid") :: Humanoid?
	if not humanoid then return false end
	
	self.component:SetAttribute("targetPosition", targetPosition)
	self:setState("walking")
	
	-- Simple movement for now - could enhance with pathfinding
	humanoid:MoveTo(targetPosition)
	return true
end

-- Start pathfinding to target
function Movement:pathfindTo(targetPosition: Vector3): boolean
	local humanoid = self.model:FindFirstChild("Humanoid") :: Humanoid?
	local humanoidRootPart = self.model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not humanoidRootPart then return false end
	
	local startPos = humanoidRootPart.Position
	local success, path = pcall(function()
		return PathfindingService:CreatePath({
			AgentRadius = 2,
			AgentHeight = 5,
			AgentCanJump = self.model:GetAttribute("CanJump") or false,
			WaypointSpacing = 4,
		}):ComputeAsync(startPos, targetPosition)
	end)
	
	if not success or not path then
		-- Fallback to simple MoveTo
		return self:moveTo(targetPosition)
	end
	
	self.currentPath = path
	self.pathIndex = 1
	self.component:SetAttribute("targetPosition", targetPosition)
	self.component:SetAttribute("lastPathUpdate", os.clock())
	
	self:_followPath()
	return true
end

-- Start patrolling around the spawn point
function Movement:startPatrolling()
	local patrolRadius = self.model:GetAttribute("PatrolRadius") or 10
	local center = self.component:GetAttribute("patrolCenter") :: Vector3
	
	-- Pick a random point within patrol radius
	local angle = math.random() * math.pi * 2
	local distance = math.random() * patrolRadius
	local offset = Vector3.new(
		math.cos(angle) * distance,
		0,
		math.sin(angle) * distance
	)
	
	local targetPos = center + offset
	self:setState("patrolling")
	self:enableWalking()
	return self:pathfindTo(targetPos)
end

-- Stop all movement
function Movement:stop()
	local humanoid = self.model:FindFirstChild("Humanoid") :: Humanoid?
	if humanoid then
		humanoid:MoveTo(self:getPosition())
	end
	
	self.currentPath = nil
	self:setState("idle")
end

-- Check if NPC has reached target
function Movement:hasReachedTarget(): boolean
	local target = self.component:GetAttribute("targetPosition") :: Vector3?
	if not target then return true end
	
	local currentPos = self:getPosition()
	local distance = (currentPos - target).Magnitude
	return distance < 3 -- 3 stud tolerance
end

-- Check if NPC is stuck (hasn't moved much recently)
function Movement:isStuck(): boolean
	local currentTime = os.clock()
	local lastCheck = self.component:GetAttribute("stuckCheckTime") or 0
	
	if currentTime - lastCheck > 2 then -- Check every 2 seconds
		local currentPos = self:getPosition()
		local lastPos = self.component:GetAttribute("lastPosition") :: Vector3
		
		local moved = (currentPos - lastPos).Magnitude
		self.component:SetAttribute("lastPosition", currentPos)
		self.component:SetAttribute("stuckCheckTime", currentTime)
		
		if moved < 1 and self:getState() ~= "idle" then
			self:setState("stuck")
			return true
		end
	end
	
	return self:getState() == "stuck"
end

-- Private: Follow the current pathfinding path
function Movement:_followPath()
	if not self.currentPath then return end
	
	local waypoints = self.currentPath:GetWaypoints()
	if self.pathIndex > #waypoints then
		-- Reached end of path
		self.currentPath = nil
		if self:getState() == "patrolling" then
			-- Continue patrolling after a brief pause
			task.wait(math.random(1, 3))
			if self:getState() == "patrolling" then -- Still patrolling
				self:startPatrolling()
			end
		else
			self:setState("idle")
		end
		return
	end
	
	local humanoid = self.model:FindFirstChild("Humanoid") :: Humanoid?
	if not humanoid then return end
	
	local waypoint = waypoints[self.pathIndex]
	humanoid:MoveTo(waypoint.Position)
	
	-- Handle jumping waypoints
	if waypoint.Action == Enum.PathWaypointAction.Jump then
		humanoid.Jump = true
	end
	
	-- Move to next waypoint when close enough
	local connection
	connection = RunService.Heartbeat:Connect(function()
		local distance = (self:getPosition() - waypoint.Position).Magnitude
		if distance < 3 then
			connection:Disconnect()
			self.pathIndex += 1
			self:_followPath()
		end
	end)
end

-- Update movement (called by system update loop)
function Movement:update(_deltaTime: number)
	-- Handle stuck detection and recovery
	if self:isStuck() then
		self:stop()
		task.wait(1)
		if self:getState() == "stuck" then
			self:setState("idle")
		end
	end
	
	-- Auto-continue patrolling if reached target
	if self:getState() == "patrolling" and self:hasReachedTarget() and not self.currentPath then
		task.wait(math.random(1, 3))
		self:startPatrolling()
	end
end

-- Static method: Update all NPCs with Movement components
function Movement.updateAll(deltaTime: number)
	for model in pairs(_Registry) do
		if model.Parent then
			local movement = Movement.get(model)
			if movement then
				movement:update(deltaTime)
			else
				_Registry[model] = nil
			end
		else
			_Registry[model] = nil
		end
	end
end

return Movement