--!strict
-- ActionConfig: Declarative binding of high-level gameplay actions to input primitives.
-- Shape is intentionally similar to Roblox's new InputContext/InputAction/InputBinding model so we can
-- later bridge or replace the manual dispatcher with the official system.

export type Binding = {
    key: Enum.KeyCode?, -- keyboard key
    mouse: Enum.UserInputType?, -- mouse button
    gamepadButton: Enum.KeyCode?, -- future extension
    type: "press" | "release" | "hold", -- simple semantic (expand later)
    meta: { [string]: any }?, -- arbitrary per-action metadata (e.g. skill name)
}

export type ActionSpec = {
    name: string,
    bindings: { Binding },
    context: string,
    consume: boolean?, -- whether to block propagation (future use)
}

export type ContextSpec = {
    name: string,
    enabled: boolean,
    priority: number, -- higher = earlier dispatch
    actions: { [string]: ActionSpec },
}

export type ActionConfigType = {
    contexts: { [string]: ContextSpec },
    order: { string }, -- explicit ordering fallback if priorities tie
    defaultContexts: { string },
}

local ActionConfig: ActionConfigType = {
    contexts = {},
    order = {},
    defaultContexts = { "Core" },
}

local function addContext(name: string, priority: number)
    ActionConfig.contexts[name] = {
        name = name,
        enabled = true,
        priority = priority,
        actions = {},
    }
    table.insert(ActionConfig.order, name)
end

local function addAction(ctx: string, spec: {
    name: string,
    bindings: { Binding },
    consume: boolean?,
    meta: { [string]: any }?,
})
    local c = ActionConfig.contexts[ctx]
    if not c then
        error("ActionConfig: context missing: " .. ctx)
    end
    c.actions[spec.name] = {
        name = spec.name,
        bindings = spec.bindings,
        context = ctx,
        consume = spec.consume,
    }
end

-- Core gameplay context (always on)
addContext("Core", 100)

-- Toggle system panel (E)
addAction("Core", {
    name = "ToggleSystemPanel",
    bindings = {
        { key = Enum.KeyCode.E, type = "press" },
    },
})

-- Cycle active skill profile (LeftAlt)
addAction("Core", {
    name = "CycleSkillProfile",
    bindings = {
        { key = Enum.KeyCode.LeftAlt, type = "press" },
    },
})

-- Cycle active skill profile backward (RightAlt)
addAction("Core", {
    name = "CycleSkillProfilePrev",
    bindings = {
        { key = Enum.KeyCode.RightAlt, type = "press" },
    },
})

-- Skill slot actions: Skill1..Skill5. Skill1 keeps mouse binding (LMB) plus key 'One'. Others use numeric keys Two..Five.
local skillKeyMap = {
    [1] = Enum.KeyCode.One,
    [2] = Enum.KeyCode.Two,
    [3] = Enum.KeyCode.Three,
    [4] = Enum.KeyCode.Four,
    [5] = Enum.KeyCode.Five,
}

for i = 1, 5 do
    local bindings: {Binding} = {
        { key = skillKeyMap[i], mouse = nil, gamepadButton = nil, type = "press" },
    }
    if i == 1 then
        table.insert(bindings, { key = nil, mouse = Enum.UserInputType.MouseButton1, gamepadButton = nil, type = "press" })
    end
    addAction("Core", {
        name = "Skill" .. tostring(i),
        bindings = bindings,
    })
end

return ActionConfig
