# Skill Timing Details

`src/server/SkillsFramework/SkillTimingService.luau` centralises tempo decisions so combat scales from stats, buffs, or temporary overrides.

## Categories and Stats

- Skill configs can set `timingCategory`. The service maps aliases (`attack`, `melee`, `spell`, etc.) to canonical categories.
- Each category resolves to a stat (for example `melee -> AttackSpeed`, `spell -> SpellCastSpeed`). The stat value becomes the base tempo.
- Observers registered in `StatsMediator` can override `tempo`, `tempoMultiplier`, or `tempoAdd` through metadata.

## Resolver Flow

1. `BaseSkill:resolveTiming` builds context metadata (skill id, tags, combo step info) and calls `SkillTimingService.resolve`.
2. The default resolver queries `StatsManager.getStatValue` with `StatsMediator` options so observers can hook `resolveSkillTempo`.
3. Tempo output is clamped (`MIN_TEMPO`, `MAX_TEMPO`) and converted into `durationScale = 1 / tempo`.

The result feeds back into `BaseSkill:_updateExecutionState`, which annotates the execution lock with `tempo`, `durationScale`, and `targetDuration` so the client can stay in sync.

## Combo Windows

`ComboService.luau` tracks per-caster state:

- `requestStep` validates cooldown windows and issues a `token` for the next step (blocking further inputs until `registerStepTiming` clears `pendingToken`).
- `registerStepTiming` stores `busyUntil`, `windowOpenAt`, and `windowCloseAt`. Non-final steps open a follow-up window where another `requestStep` is allowed.
- `isTokenCurrent` lets skills verify the current token before emitting wait indicators or expiring executions.

Separation between timing resolution and combo gating ensures server authority over both execution duration and player input windows.
