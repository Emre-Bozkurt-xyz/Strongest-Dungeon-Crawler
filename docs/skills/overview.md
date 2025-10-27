# Skills Framework Overview

This project splits combat skills across multiple modules so that server timing, resource spending, and client FX remain deterministic.

## Layout

- `src/server/SkillsFramework/SkillsData/` contains declarative skill definitions. Each module returns a table with `name`, `cooldown`, `combo`, and other metadata. Add new skills here before writing any code.
- `src/server/SkillsFramework/SkillsConfig.luau` loads the data modules, applies optional overrides, and instantiates skill classes.
- `src/server/SkillsFramework/Skills/` provides the behaviour modules:
  - `BaseSkill.luau` handles execution locks, timing resolution, dispatcher events, and resource costs.
  - `BaseComboSkill.luau` builds on `BaseSkill` for multi-step combos, deriving per-step timings and registering windows with `ComboService`.
  - Individual skills (for example `Punch.luau`, `TripleStrike.luau`) implement `use` and `onComboStep` to schedule hitboxes, damage, and FX.
- `src/server/SkillsFramework/SkillsManager.luau` wires everything together. It answers `SkillsRequest` dispatcher calls, enforces cooldowns, and starts/stops executions in `ExecutionService`.

## Timing Pipeline

1. `SkillsManager.useSkill` validates cooldowns and execution locks, then calls `ComboService.requestStep` if the skill has combo metadata.
2. `BaseSkill:resolveTiming` consults `SkillTimingService.luau` to determine tempo and duration scale. Timing categories map to stats (for example `AttackSpeed`) via `StatsMediator`.
3. `BaseComboSkill` records the authoritative step duration, window, and recovery. It then calls `ComboService.registerStepTiming` so that the controller can enforce busy windows before the next `requestStep`.
4. `ExecutionService` owns the execution lock and raises the completion event that starts both per-skill cooldown and global cooldown in `CooldownService`.

The server always starts cooldowns inside the `ExecutionService.onCompleted` listener. Individual skill modules should never call `CooldownService` directly.

## Resource Costs

`BaseSkill:applyResourceCost` queries stats, previews any overrides (`StatsManager.resolvePoolCost`), and finally debits the target pool. If cost removal fails on step one, `ComboService.clear` resets progress so the next attempt restarts the chain.

## Client Coordination

Server skills emit dispatcher events via `SkillsEvent`. The client side (`src/client/SkillsFramework/SkillsClient.luau`) receives phases (`start`, `step`, `combo_wait`, `fx`, `end`) and forwards tempo metadata to:

- `src/client/fx/AnimationPlayer.luau`, which pulls native clip lengths via `AssetLoader` and adjusts tempo per step.
- `src/client/fx/FXPlayer.luau`, which plays particles and sounds when server events arrive.

`src/client/init.client.luau` must call `AssetLoader.init()` before any skill events fire so animations have cached native lengths on first use.
