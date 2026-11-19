--!strict

-- Clip name -> published animation ID, declared by the module that owns the clips (an attack
-- profile or a skill spec). `false` declares a clip that has no published ID yet: references to it
-- still validate, live servers play nothing, and Studio playtests stand in a draft KeyframeSequence
-- of the same full name (see AnimationRegistry).
export type ClipSet = { [string]: string | false }

return {}
