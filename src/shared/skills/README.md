This folder holds client-facing, data-only specs for skills.

- ClientSpec.luau: map of skillId -> visual keys
  - anim: start/impact[n]/finish strings
  - fx:    impact[n] strings
  - sfx:   optional sound keys

Server skill behavior lives in src/server/SkillsFramework (class-based).
Remove the old shared/skills/defs and Definitions if you no longer need them.
