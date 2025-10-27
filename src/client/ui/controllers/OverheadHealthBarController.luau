--!strict
local TweenService = game:GetService("TweenService")

export type OverheadHealthBarController = {
    -- instance fields
    part: BasePart,
    gui: BillboardGui,
    frame: Frame,
    progress: Frame,
    fill: GuiObject,
    nameLabel: TextLabel?,
    curLabel: TextLabel?,
    maxLabel: TextLabel?,
    percentageLabel: TextLabel?,
    _tween: Tween?,
    _fadeTween: Tween?,
    _fadeToken: number,
    setPercent: (self: OverheadHealthBarController, p: number) -> (),
    setCurrentMax: (self: OverheadHealthBarController, cur: number, max: number) -> (),
    setName: (self: OverheadHealthBarController, name: string) -> (),
    setAlphaMultiplier: (self: OverheadHealthBarController, a: number) -> (),
    show: (self: OverheadHealthBarController) -> (),
    hide: (self: OverheadHealthBarController) -> (),
    destroy: (self: OverheadHealthBarController) -> (),
    -- internal/private fields for strict mode
    _fadeAlpha: number,
    _densityAlpha: number,
    _isHidden: boolean,
    -- cached base transparencies so fading never overrides intended visuals
    _baseFrameBgT: number,
    _baseProgressBgT: number,
    _baseFillBgT: number,
    _baseNameTextT: number,
    _baseCurTextT: number,
    _baseMaxTextT: number,
    _applyVisualAlpha: (self: OverheadHealthBarController, a: number) -> (),
    _getFinalAlpha: (self: OverheadHealthBarController) -> number,
}

local OverheadHealthBarController = {}
OverheadHealthBarController.__index = OverheadHealthBarController

-- Expected hierarchy (robust to variants):
--  Part -> (BillboardGui|SurfaceGui|WorldGUI) -> (HealthBar|Frame) -> ProgressBar -> (FillPanel|Fill|FillBar)
--  Labels optional: NameLabel, CurLabel, MaxLabel under the main frame

function OverheadHealthBarController.new(rootPart: BasePart)
    local self: OverheadHealthBarController = setmetatable({} :: any, OverheadHealthBarController)

    self.part = rootPart
    -- Find a GUI container (BillboardGui preferred, fallback to SurfaceGui or named children)
    local worldGui = (rootPart:FindFirstChildOfClass("BillboardGui")
        or rootPart:FindFirstChildOfClass("SurfaceGui")
        or rootPart:FindFirstChild("WorldGUI")
        or rootPart:FindFirstChild("SurfaceGui"))
    if not worldGui then
        -- As a last resort, wait briefly for any GUI child
        worldGui = rootPart:WaitForChild("WorldGUI", 1)
            or rootPart:WaitForChild("SurfaceGui", 1)
            or rootPart:FindFirstChildOfClass("BillboardGui")
            or rootPart:FindFirstChildOfClass("SurfaceGui")
    end
    self.gui = worldGui :: any

    -- Resolve main frame
    local frame = (worldGui :: any) and (((worldGui :: any):FindFirstChild("HealthBar"))
        or ((worldGui :: any):FindFirstChild("Frame")))
    if not frame then
        -- first Frame descendant
        for _, d in ipairs((worldGui and (worldGui :: Instance):GetDescendants()) or {}) do
            if d:IsA("Frame") then
                frame = d
                break
            end
        end
    end
    self.frame = (frame or Instance.new("Frame")) :: any

    -- Resolve progress container
    local progress = frame and (((frame :: any):FindFirstChild("ProgressBar")) or ((frame :: any):FindFirstChild("Bar")))
    if not progress then
        progress = frame
    end
    self.progress = (progress or Instance.new("Frame")) :: any

    -- Resolve fill panel
    local fill = progress and (((progress :: any):FindFirstChild("FillPanel"))
        or ((progress :: any):FindFirstChild("Fill"))
        or ((progress :: any):FindFirstChild("FillBar")))
    if not fill then
        -- search for any GuiObject with "Fill" in name
        for _, d in ipairs((progress and (progress :: Instance):GetChildren()) or {}) do
            if d:IsA("GuiObject") and string.find(d.Name:lower(), "fill") then
                fill = d
                break
            end
        end
    end
    self.fill = fill :: GuiObject

    self.nameLabel = frame:FindFirstChild("NameLabel") :: TextLabel?
    self.curLabel = frame:FindFirstChild("CurLabel") :: TextLabel?
    self.maxLabel = frame:FindFirstChild("MaxLabel") :: TextLabel?
    self.percentageLabel = frame:FindFirstChild("PercentageLabel") :: TextLabel?

    self._tween = nil
    self._fadeTween = nil
    -- Alpha blending channels
    self._fadeAlpha = 0.0 -- animated by show/hide
    self._densityAlpha = 1.0 -- set by service crowding logic
    self._isHidden = true
    -- cache base transparencies
    self._baseFrameBgT = (self.frame and self.frame.BackgroundTransparency) or 0
    self._baseProgressBgT = (self.progress and self.progress.BackgroundTransparency) or 0
    self._baseFillBgT = (self.fill and self.fill.BackgroundTransparency) or 0
    self._baseNameTextT = (self.nameLabel and self.nameLabel.TextTransparency) or 0
    self._baseCurTextT = (self.curLabel and self.curLabel.TextTransparency) or 0
    self._baseMaxTextT = (self.maxLabel and self.maxLabel.TextTransparency) or 0
    self._fadeToken = 0

    -- Start hidden (final alpha 0)
    OverheadHealthBarController._applyVisualAlpha(self, 0)

    return self
end

-- Internal: apply final alpha immediately to all visual descendants
function OverheadHealthBarController._applyVisualAlpha(self: OverheadHealthBarController, a: number)
    -- fade rule: newT = lerp(1, baseT, a)
    local function fadeT(baseT: number, alpha: number): number
        return (1 - alpha) + baseT * alpha
    end

    -- background transparencies on known frames
    if self.frame and (self.frame :: any).BackgroundTransparency ~= nil then
        (self.frame :: any).BackgroundTransparency = fadeT(self._baseFrameBgT, a)
    end
    if self.progress and (self.progress :: any).BackgroundTransparency ~= nil then
        (self.progress :: any).BackgroundTransparency = fadeT(self._baseProgressBgT, a)
    end
    if self.fill and (self.fill :: any).BackgroundTransparency ~= nil then
        (self.fill :: any).BackgroundTransparency = fadeT(self._baseFillBgT, a)
    end

    -- text labels
    if self.nameLabel and (self.nameLabel :: any).TextTransparency ~= nil then
        (self.nameLabel :: any).TextTransparency = fadeT(self._baseNameTextT, a)
    end
    if self.curLabel and (self.curLabel :: any).TextTransparency ~= nil then
        (self.curLabel :: any).TextTransparency = fadeT(self._baseCurTextT, a)
    end
    if self.maxLabel and (self.maxLabel :: any).TextTransparency ~= nil then
        (self.maxLabel :: any).TextTransparency = fadeT(self._baseMaxTextT, a)
    end
end

function OverheadHealthBarController._getFinalAlpha(self: OverheadHealthBarController): number
    return self._fadeAlpha * self._densityAlpha
end

function OverheadHealthBarController:setAlphaMultiplier(a: number)
    self._densityAlpha = math.clamp(a, 0, 1)
    OverheadHealthBarController._applyVisualAlpha(self, OverheadHealthBarController._getFinalAlpha(self))
end

function OverheadHealthBarController:show()
    if not self._isHidden then
        -- Already showing
        return
    end
    if self._fadeTween then
        self._fadeTween:Cancel()
    end
    -- Fade to 1 over 0.2s
    -- We tween via stepping transparency on descendants; simplify to a single tween call that we run manually
    local duration = 0.2
    local start = self._fadeAlpha
    local goal = 1.0
    local driver = Instance.new("NumberValue")
    driver.Value = start
    local curToken: number = (self :: any)._fadeToken
    local token: number = curToken + 1
    (self :: any)._fadeToken = token
    self._fadeTween = TweenService:Create(driver, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Value = goal })
    self._fadeTween:Play()
    local conn: RBXScriptConnection? = nil
    conn = driver:GetPropertyChangedSignal("Value"):Connect(function()
        if self._fadeToken ~= token then
            if conn then
                conn:Disconnect()
            end
            return
        end
        self._fadeAlpha = driver.Value
        local alpha = OverheadHealthBarController._getFinalAlpha(self)
        OverheadHealthBarController._applyVisualAlpha(self, alpha)
    end)
    task.spawn(function()
        if self._fadeTween then
            self._fadeTween.Completed:Wait()
        end
        if self._fadeToken ~= token then
            return
        end
        self._fadeAlpha = 1
        OverheadHealthBarController._applyVisualAlpha(self, OverheadHealthBarController._getFinalAlpha(self))
        self._isHidden = false
        if conn then
            conn:Disconnect()
        end
        driver:Destroy()
        self._fadeTween = nil
    end)
end

function OverheadHealthBarController:hide()
    if self._isHidden then
        -- Already hidden
        return
    end
    if self._fadeTween then
        self._fadeTween:Cancel()
    end
    local duration = 0.2
    local start = self._fadeAlpha
    local goal = 0.0
    local driver = Instance.new("NumberValue")
    driver.Value = start
    local curToken2: number = (self :: any)._fadeToken
    local token: number = curToken2 + 1
    (self :: any)._fadeToken = token
    self._fadeTween = TweenService:Create(driver, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Value = goal })
    self._fadeTween:Play()
    local conn: RBXScriptConnection? = nil
    conn = driver:GetPropertyChangedSignal("Value"):Connect(function()
        if self._fadeToken ~= token then
            if conn then
                conn:Disconnect()
            end
            return
        end
        self._fadeAlpha = driver.Value
        local alpha = OverheadHealthBarController._getFinalAlpha(self)
        OverheadHealthBarController._applyVisualAlpha(self, alpha)
    end)
    task.spawn(function()
        if self._fadeTween then
            self._fadeTween.Completed:Wait()
        end
        if self._fadeToken ~= token then
            return
        end
        self._fadeAlpha = 0
        OverheadHealthBarController._applyVisualAlpha(self, 0)
        self._isHidden = true
        if conn then
            conn:Disconnect()
        end
        driver:Destroy()
        self._fadeTween = nil
    end)
end

function OverheadHealthBarController:setName(name: string)
    if self.nameLabel and (self.nameLabel :: any).Text ~= nil then
        (self.nameLabel :: any).Text = name
    end
end

function OverheadHealthBarController:setPercent(p: number)
    p = math.clamp(p, 0, 1)
    if not self.fill then
        return
    end
    if self._tween then
        self._tween:Cancel()
    end
    self._tween = TweenService:Create(self.fill, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Size = UDim2.fromScale(p, 1),
    })
    self._tween:Play()
    if self.curLabel then
        self.curLabel.Text = ""
    end
    if self.maxLabel then
        self.maxLabel.Text = ""
    end
    if self.percentageLabel then
        self.percentageLabel.Text = tostring(math.floor(p * 100)) .. "%"
    end
end

function OverheadHealthBarController:setCurrentMax(cur: number, max: number)
    cur = math.clamp(cur, 0, math.max(1, max))
    local p = cur / math.max(1, max)
    if not self.fill then
        return
    end
    if self._tween then
        self._tween:Cancel()
    end
    self._tween = TweenService:Create(self.fill, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Size = UDim2.fromScale(p, 1),
    })
    self._tween:Play()

    if self.percentageLabel then
        self.percentageLabel.Text = ""
    end

    if self.curLabel then
        self.curLabel.Text = tostring(math.floor(cur))
    end
    if self.maxLabel then
        self.maxLabel.Text = "/" .. tostring(math.floor(max))
    end
end

function OverheadHealthBarController:destroy()
    if self._tween then
        self._tween:Cancel()
    end
    if self._fadeTween then
        self._fadeTween:Cancel()
    end
    -- Part is destroyed by caller (service)
end

return OverheadHealthBarController
