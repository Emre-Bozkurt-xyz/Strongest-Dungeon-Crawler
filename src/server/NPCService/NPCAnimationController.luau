-- NPCAnimationController: Plays NPC animations for skills using category mapping with per-skill overrides.
-- Spec structure (per NPC):
-- animations = {
--   attack = {
--     default = { "rbxassetid://..." },
--     bySkill = { Punch = { ... } },
--     byCategory = { melee_light = { ... } },
--   },
--   -- future: walking, crouching, etc.
-- }

-- Server-side only; references SkillsFramework for animCategory lookup
local SkillsConfig = require(script.Parent.Parent.SkillsFramework.SkillsConfig)

local Controller = {}

type AnimSet = { [string]: { string } } -- category -> list of animation keys
type AttackAnimSpec = { default: { string }?, bySkill: { [string]: { string } }?, byCategory: AnimSet? }
type NPCAnimSpec = { attack: AttackAnimSpec? }

local _specAnims: { [Model]: NPCAnimSpec } = {}

local function _getAnimator(model: Model): Animator?
    local hum = model:FindFirstChildOfClass("Humanoid")
    if not hum then return nil end
    local animator = hum:FindFirstChildOfClass("Animator")
    if not animator then
        animator = Instance.new("Animator")
        animator.Parent = hum
    end
    return animator
end

local function _loadAndPlay(animator: Animator, animId: string)
    local anim = Instance.new("Animation")
    anim.AnimationId = animId
    local track = animator:LoadAnimation(anim)
    track:Play()
    task.delay(0, function()
        anim:Destroy()
    end)
end

local function _pick(list: { string }?): string?
    if not list or #list == 0 then return nil end
    if #list == 1 then return list[1] end
    return list[math.random(1, #list)]
end

-- Public API
function Controller.registerNPC(model: Model, anims: NPCAnimSpec)
    _specAnims[model] = anims
    model.Destroying:Connect(function()
        _specAnims[model] = nil
    end)
end

function Controller.onSkillStart(model: Model, skillName: string)
    local data = _specAnims[model]
    if not data then return end
    local attack = data.attack
    if not attack then return end
    local animator = _getAnimator(model)
    if not animator then return end

    -- Prefer explicit per-skill mapping
    local overrideList = attack.bySkill and attack.bySkill[skillName]
    if overrideList and #overrideList > 0 then
        local id = _pick(overrideList)
        if id then
            _loadAndPlay(animator, id)
        end
        return
    end

    -- Otherwise use the skill category if available
    local sd = SkillsConfig.skills[skillName]
    local cat = sd and sd.animCategory
    if cat and attack.byCategory then
        local id = _pick(attack.byCategory[cat])
        if id then
            _loadAndPlay(animator, id)
            return
        end
    end

    -- Fallback to default
    local def = _pick(attack.default)
    if def then
        _loadAndPlay(animator, def)
    end
end

return Controller
