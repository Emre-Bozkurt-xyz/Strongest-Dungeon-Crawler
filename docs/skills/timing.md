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

The result feeds into `BaseSkill` timing calculations, producing `durationScale` and per-step durations used by `SessionManager` and client prediction.

## Combo Windows

`SessionManager.luau` tracks per-caster combo state inside the active session:

- `advanceCombo` validates the current window and increments `currentStep`/`stepToken`.
- `extendComboWindow` sets `windowOpensAt` and `windowExpiresAt` for the next input.
- The heartbeat loop expires windows and completes sessions deterministically.

Clients read the same window data via `SessionMirror`, keeping combo gating consistent across server and client.
