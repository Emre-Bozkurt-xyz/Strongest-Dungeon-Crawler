local TS = game:GetService("TweenService")

local StaminaBarController = {}
StaminaBarController.__index = StaminaBarController

function StaminaBarController.new(Parent: Instance)
    local self = setmetatable({}, StaminaBarController)

    -- Initialize stamina bar UI elements
    self.staminaBar = Parent:WaitForChild("StaminaBar")
    self.left = self.staminaBar:WaitForChild("Left"):WaitForChild("Circle")
    self.right = self.staminaBar:WaitForChild("Right"):WaitForChild("Circle")
    self.centerCircle = self.staminaBar:WaitForChild("Center")

    self.lastRotation = 0

    return self
end

function StaminaBarController:updateStamina(stam, maxStam)
    local rotation = math.floor(math.clamp(stam / maxStam * 360, 0, 360))

    local rightTimeRatio = 1
    local leftTimeRatio = 1

    local rotationDiff = math.abs(self.lastRotation - rotation)

    if self.lastRotation > 180 and rotation < 180 then
        leftTimeRatio = (self.lastRotation - 180) / rotationDiff
        rightTimeRatio = (180 - rotation) / rotationDiff
    elseif self.lastRotation < 180 and rotation > 180 then
        leftTimeRatio = (rotation - 180) / rotationDiff
        rightTimeRatio = (180 - self.lastRotation) / rotationDiff
    end

    -- Total tween time is 0.3 seconds
    -- We adjusted the tween time for each side based on their ratio of change
    local leftTween = TS:Create(
        self.left.UIGradient,
        TweenInfo.new(0.15 * leftTimeRatio, Enum.EasingStyle.Linear),
        { Rotation = math.clamp(rotation, 180, 360) }
    )
    local rightTween = TS:Create(
        self.right.UIGradient,
        TweenInfo.new(0.15 * rightTimeRatio, Enum.EasingStyle.Linear),
        { Rotation = math.clamp(rotation, 0, 180) }
    )

    if self.lastRotation > rotation then
        leftTween:Play()
        leftTween.Completed:Wait()
        rightTween:Play()
    else
        rightTween:Play()
        rightTween.Completed:Wait()
        leftTween:Play()
    end

    self.lastRotation = rotation
end

return StaminaBarController
