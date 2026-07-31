# Charging as CASTING — open the skill session on press, not on release

Status: **designed, not implemented.** Written as a handoff so this can be picked up cold.

## The problem

Held/charged skills (`ManaBall`, `CascadingManaBalls`) are invisible to everything until the moment
they fire. The session is created when the skill *executes*, which for a held skill is on release, so
while the player is building up:

- the HUD shows no active state — the slot looks idle
- the server does not know the character is doing anything
- stagger cannot interrupt the charge, because there is nothing to interrupt

The last point is the reason this matters beyond cosmetics. A character winding up a skill is a
combat-relevant state: enough stagger applied during that window *should* interrupt it, the same way
it interrupts a cast.

`ChargeSpec` in `src/shared/skills/SkillSpecTypes.luau` is **not** related — it describes the orbiting
mana-ball visuals, not an input state.

## The decision

**Do not add a `CHARGING` state. Treat charging as `CASTING`.**

Charging and casting are the same thing behaviourally — a wind-up before an effect, interruptible
throughout — and they should look identical in the UI. Adding a state would mean a new
`SessionState`, a new `LegalTransitionsMap` entry, new client handling and a protocol change, all to
express something the existing state already means.

### Why this works

`CASTING → ACTIVE` is **event-driven, not timed**:

```luau
-- src/server/SkillsFramework/Skills/BaseSkill.luau, startExecution
SessionManager.transition(self._sessionId, "ACTIVE", "execution_started")
```

Nothing times a session out of `CASTING`. A session can therefore sit in `CASTING` for an arbitrary
hold, and release moves it to `ACTIVE` when execution begins. **Verify this is still true before
implementing** — if a `castTime` timer is ever added that auto-advances out of `CASTING`, a held
skill would fall out of the state mid-hold and this design breaks.

## The change

Open the session on **press** instead of on execution:

- `src/server/SkillsFramework/Skills/BaseSkill.luau` — session creation moves from the execution path
  to the activate/press path for held skills.
- `src/server/SkillsFramework/SessionManager.luau` — `createSession` already produces `CASTING`
  (line ~298), so no change to the created state itself.
- Client mirror: none needed. `SessionMirror` already tracks whatever the server sends.

### What comes free

- **Interrupts during charge** — stagger already operates on sessions, no new logic.
- **The HUD indicator** — `src/client/ui/hooks/useActiveSkill.luau` already lights on any
  non-terminal session, so the skill slot's active state starts working with no UI change at all.
- **`canStartSkill()`** already returns false for any non-terminal session, so a charging player is
  correctly treated as occupied.

## The hazard — design for this first

`SessionManager.canStartSkill()` returns false for *any* non-terminal session, so **a charge session
that never closes locks the player out of every skill, not just the one being charged.** That failure
mode does not exist today because nothing opens a session early.

Every path out of a charge must close the session:

- player dies or is interrupted mid-charge
- character despawns / player leaves
- the client disconnects while holding
- **the client simply never sends a release** — this one needs a server-side maximum charge duration.
  Do not rely on the client to close what it opened.

A stuck-session watchdog is worth having regardless, since it is the difference between a bug and an
unplayable character.

## Testing notes

- Hold `CascadingManaBalls`: slot should light on press, stay lit through the hold, and stay lit
  while the balls fire, going dark only at the end.
- Get staggered mid-charge: the charge should be interrupted and the session cancelled.
- Release, then immediately try another skill: no lockout.
- Kill the character mid-charge, respawn, try any skill: no lockout.

## Related UI already in place

`useActiveSkill` deliberately delays *releasing* the active state by 150ms (`RELEASE_GRACE`) because
the session drops to nil for a frame or two across the predicted-to-authoritative handoff and between
combo steps. If the flicker persists after this change, the root cause is in
`SessionMirror.predictStart` / reconciliation, not the hook.
