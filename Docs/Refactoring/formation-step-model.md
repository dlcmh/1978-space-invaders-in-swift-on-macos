# Stepping the formation as one unit

- **Project:** SPACE INVADERS — Metal Arcade
- **Recorded:** 2026-10-20 (+08:00, Asia/Kuala_Lumpur)
- **Last updated:** 2026-10-20
- **Status:** Accepted

## Proposal

Model each of the 55 invaders as an independent marcher, the way the original
hardware advanced one invader per video frame. Each alien would carry its own
pending-step timer and animation phase.

## Alternatives considered

1. **Per-alien asynchronous timers.** The closest surface-level match to the
   original's one-sprite-per-frame update. Every alien would own a timer, a
   direction, and a position update.
2. **One formation timer, all survivors step together.** The current model.
   `updateFormation` fires on a single `marchTimer` and `stepFormation` moves
   all living invaders by the same amount.

## Evidence

- The gameplay-visible result is identical at 60 Hz: the formation visibly
  steps sideways and drops as one block. The original's staggered update is a
  hardware artifact, not a rule a player can act on.
- One timer makes the acceleration rule explicit in `marchInterval`; with 55
  timers the effective speed would be emergent and much harder to tune or
  explain.
- Determinism is simpler. A single `formationSteps` counter and
  `animationFrame` give the checks a stable observable, and no alien's phase can
  drift because of floating-point accumulation in a different update order.
- Collision and bunker erosion stay coherent. `eraseBunkersUnderInvaders` runs
  once after the whole formation has moved, so a survivor cannot erase a cell
  with a half-step position that is immediately overwritten.
- The code path is substantially smaller: no per-alien timer storage, no
  per-alien sort, and no risk of an invader being skipped when the catch-up loop
  runs multiple steps.

## Decision

Keep the single formation step. The cost is that the march animates in whole
formation ticks rather than one sprite at a time; the benefit is a deterministic,
explainable speed model and a much smaller state machine.

## How to revisit

If a future change wants the original's staggered texture, add it as a
**presentation-only** offset: keep `stepFormation` authoritative, and let
`drawAliens` delay a sprite's visual position by a fraction of the current
`marchInterval`. Do not move the collision positions onto per-alien timers
without reworking `eraseBunkersUnderInvaders` and the wave-clear checks.
