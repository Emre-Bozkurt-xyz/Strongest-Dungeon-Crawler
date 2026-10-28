--!strict
-- LoadoutDragController: dragging a skill between the Loadout's two panels.
--
-- The skills panel sits beside the Loadout in the Loadout's own plane (MenuRigRuntime places side
-- panels that way), and the camera holds still while the menu is open. So a drag is one ray from the
-- camera through the cursor, hitting that plane: a point that moves smoothly from one panel onto the
-- other, with no seam between them to blend across. The carried skill is drawn at that point, just
-- off the plane toward the camera, and the slot under it is found from the bar's own buttons.
--
-- A press that never travels PRESS_SLOP pixels stays a click and is left to the button.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local React = require(ReplicatedStorage.Packages.React)

local CombatLoadoutMirror = require(script.Parent.Parent.Parent.Inventory.CombatLoadoutMirror)
local mountPanel = require(script.Parent.Parent.app.mountPanel)
local ThemeContext = require(script.Parent.Parent.hooks.ThemeContext)
local SkillPicture = require(script.Parent.Parent.components.SkillPicture)
local skillLook = require(script.Parent.Parent.selectors.skillLook)
local LoadoutEditController = require(script.Parent.LoadoutEditController)

local e = React.createElement

local LOADOUT_PANEL = "LoadoutPanel"
local SKILLS_PANEL = "LoadoutSkillsPanel"
-- Screen pixels a press travels before it is a drag.
local PRESS_SLOP = 6
-- Studs off the panels' plane toward the camera, so the carried skill lies over them.
local LIFT = 0.12
-- Studs square: a little smaller than a slot, so the slot it is over shows around it.
local GHOST_SIZE = 0.6
local GHOST_PIXELS_PER_STUD = 200
-- An Activated this soon after a drag ended belongs to the drag's release, not to a click.
local CLICK_GRACE = 0.15

local LoadoutDragController = {}

type Press = {
	skill: string,
	from: number?,
	origin: Vector2,
	moved: boolean,
}

local slotGuis: { [number]: GuiObject } = {}
local press: Press? = nil
local connections: { RBXScriptConnection } = {}
local endedAt = 0

type Ghost = { part: BasePart, gui: SurfaceGui, mounted: mountPanel.MountedPanel }
local ghost: Ghost? = nil

local function GhostTile(props: { look: skillLook.Look })
	local theme = ThemeContext.useTheme()
	return e("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = theme.color.skillSlotSurface,
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
	}, {
		Stroke = e("UIStroke", {
			Color = theme.color.accentTo,
			Thickness = 3,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		Picture = e(SkillPicture, {
			look = props.look,
			size = UDim2.fromScale(0.62, 0.62),
			color = theme.color.textPrimary,
		}),
	})
end

local function ensureGhost(): Ghost
	local existing = ghost
	if existing then
		return existing
	end
	local part = Instance.new("Part")
	part.Name = "LoadoutDragGhost"
	part.Size = Vector3.new(GHOST_SIZE, GHOST_SIZE, 0.05)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = GHOST_PIXELS_PER_STUD
	gui.LightInfluence = 0
	gui.Active = false
	gui.Enabled = false
	gui.Adornee = part
	gui.Parent = part
	part.Parent = Workspace
	local made = { part = part, gui = gui, mounted = mountPanel(gui, nil) }
	ghost = made
	return made
end

local function panelPart(id: string): BasePart?
	local found = Workspace:FindFirstChild(id)
	return if found and found:IsA("BasePart") then found else nil
end

-- Where the cursor's ray meets `part`'s face plane.
local function hitPlane(part: BasePart): Vector3?
	local camera = Workspace.CurrentCamera
	if not camera then
		return nil
	end
	local mouse = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
	local normal = part.CFrame.LookVector
	local facing = ray.Direction:Dot(normal)
	if math.abs(facing) < 1e-4 then
		return nil
	end
	local distance = (part.Position - ray.Origin):Dot(normal) / facing
	return if distance > 0 then ray.Origin + ray.Direction * distance else nil
end

-- A world point on `part`'s front face, in its SurfaceGui's pixels. The face is the part's -Z, so
-- a reader's left edge of the surface is the part's +X.
local function surfacePixel(part: BasePart, gui: SurfaceGui, world: Vector3): Vector2
	local at = part.CFrame:PointToObjectSpace(world)
	return Vector2.new((part.Size.X / 2 - at.X) * gui.PixelsPerStud, (part.Size.Y / 2 - at.Y) * gui.PixelsPerStud)
end

local function within(part: BasePart, world: Vector3): boolean
	local at = part.CFrame:PointToObjectSpace(world)
	return math.abs(at.X) <= part.Size.X / 2 and math.abs(at.Y) <= part.Size.Y / 2
end

local function slotUnder(world: Vector3): number?
	local part = panelPart(LOADOUT_PANEL)
	local gui = part and part:FindFirstChildOfClass("SurfaceGui")
	if not (part and gui) then
		return nil
	end
	local pixel = surfacePixel(part, gui, world)
	for index, slot in pairs(slotGuis) do
		local min = slot.AbsolutePosition
		local max = min + slot.AbsoluteSize
		if pixel.X >= min.X and pixel.X <= max.X and pixel.Y >= min.Y and pixel.Y <= max.Y then
			return index
		end
	end
	return nil
end

local function disconnectAll()
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
end

local function hideGhost()
	local made = ghost
	if made then
		made.gui.Enabled = false
		made.mounted.render(nil)
	end
end

local function finish()
	disconnectAll()
	hideGhost()
	if press and press.moved then
		endedAt = os.clock()
	end
	press = nil
	LoadoutEditController.setDrag(nil, nil)
end

local function step()
	local current = press
	local part = panelPart(LOADOUT_PANEL)
	if not (current and current.moved and part) then
		return
	end
	local world = hitPlane(part)
	if not world then
		return
	end
	local made = ensureGhost()
	made.part.CFrame = part.CFrame.Rotation + world + part.CFrame.LookVector * LIFT
	local dropSlot = slotUnder(world)
	local state = LoadoutEditController.get()
	if state.dropSlot ~= dropSlot or state.dragging == nil then
		LoadoutEditController.setDrag(state.dragging or { skill = current.skill, from = current.from }, dropSlot)
	end
end

local function lift(current: Press)
	current.moved = true
	local made = ensureGhost()
	made.mounted.render(e(GhostTile, { look = skillLook(current.skill, CombatLoadoutMirror.get()) }))
	made.gui.Enabled = true
	LoadoutEditController.setDrag({ skill = current.skill, from = current.from }, nil)
	step()
end

local function release()
	local current = press
	if not (current and current.moved) then
		finish()
		return
	end
	local part = panelPart(LOADOUT_PANEL)
	local world = part and hitPlane(part)
	local dropSlot = if world then slotUnder(world) else nil
	local skills = panelPart(SKILLS_PANEL)
	local skillsWorld = skills and hitPlane(skills)
	local overSkills = skills ~= nil and skillsWorld ~= nil and within(skills, skillsWorld)
	finish()
	if dropSlot then
		LoadoutEditController.place(dropSlot, current.skill)
	elseif current.from and overSkills then
		-- Dragged off the bar back into the list: take it out.
		LoadoutEditController.clear(current.from)
	end
end

-- The bar's slot buttons, so a drop can be matched to the slot it lands on. Returns an unregister.
function LoadoutDragController.registerSlot(index: number, gui: GuiObject): () -> ()
	slotGuis[index] = gui
	return function()
		if slotGuis[index] == gui then
			slotGuis[index] = nil
		end
	end
end

-- A press on a skill in the list, or on a filled slot (`from`). It becomes a drag once it moves.
function LoadoutDragController.press(skill: string, from: number?)
	finish()
	local mouse = UserInputService:GetMouseLocation()
	local current: Press = { skill = skill, from = from, origin = mouse, moved = false }
	press = current
	table.insert(
		connections,
		UserInputService.InputChanged:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.MouseMovement or current.moved then
				return
			end
			if (UserInputService:GetMouseLocation() - current.origin).Magnitude >= PRESS_SLOP then
				lift(current)
			end
		end)
	)
	table.insert(
		connections,
		UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				release()
			end
		end)
	)
	table.insert(connections, RunService.RenderStepped:Connect(step))
end

-- True while a drag is under way or has just been dropped: the button it was released over still
-- fires Activated, which is not a click.
function LoadoutDragController.isDragging(): boolean
	return (press ~= nil and press.moved) or os.clock() - endedAt < CLICK_GRACE
end

function LoadoutDragController.cancel()
	if press then
		finish()
	end
end

Players.LocalPlayer.CharacterRemoving:Connect(LoadoutDragController.cancel)

return LoadoutDragController
