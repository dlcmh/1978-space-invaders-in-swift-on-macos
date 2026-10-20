# When does the check suite run, and why then?

- **Project:** SPACE INVADERS — Metal Arcade
- **Recorded:** 2026-10-20 (+08:00, Asia/Kuala_Lumpur)
- **Last updated:** 2026-10-20

Every `check(...)` call in the suite runs **when the `SpaceInvadersChecks`
executable starts**, before it can do anything else, once, in file order, on one
thread. There is no test runner, no discovery phase, no per-test setup and
teardown. The gate runs it as stage 3 of 4, after lint and the release build and
before the docs check.

### The mechanism

[`main.swift`](../../Checks/main.swift) — `check` is the whole harness. It
increments a global counter, prints `FAIL: <message>` and calls `exit(1)` on the
first false condition, and does nothing on success.

[`Package.swift`](../../Package.swift) — `SpaceInvadersChecks` is an
`executableTarget` whose `path` is `Checks`, so `main.swift` is the program.
Swift treats top-level statements in `main.swift` as `main()`, which is why the
scenarios are plain statements rather than functions someone calls.

[`make check`](../../Makefile) — `checks` is `swift run SpaceInvadersChecks`, and
`check` is `./scripts/check.sh`.

| Trigger | Runs the suite? | Why |
| --- | --- | --- |
| `swift run SpaceInvadersChecks` | yes | It is the executable |
| `make checks` | yes | Same command |
| `make check` | yes | Stage 3 of the gate |
| `swift build` | no | Compiles the target, does not launch it |
| `swift run SpaceInvadersArcade` | no | The game never imports the checks |
| `swift test` | n/a | There is no test target |

`swift run` builds first when sources changed, so the suite always executes the
current code rather than a stale binary.

### Why that point in the gate

[`check.sh`](../../scripts/check.sh) — `swift-format` lints, the release build
runs with `-warnings-as-errors`, then the checks, then `check_docs.py`. The order
is fail-fast by cost and dependency:

| Stage | Catches | Cost | Why here |
| --- | --- | --- | --- |
| 1. `swift-format lint` | Style drift, long lines | seconds | Cheapest; a formatting failure is not worth compiling for |
| 2. Release build, warnings as errors | Unused variables, dead stores, actor-isolation warnings | seconds | A broken build makes every later stage meaningless |
| 3. `SpaceInvadersChecks` | Behaviour regressions | about a second | Needs a built core, and is the first stage that can say the game is *wrong* rather than *malformed* |
| 4. `docs-check` | Dead links, stale symbols | under a second | Documentation is the least urgent failure and the cheapest to fix |

The script uses `set -eu`, so a nonzero exit from `check` stops the gate; the
shell reports failure and nothing after it runs. That is why `check` can exit on
the first bad assertion instead of collecting a report.

One nuance: stage 2 compiles **release**, but stage 3 runs `swift run` without
`-c release`, so the checks execute the **debug** build. Behaviour is the same by
design, but an optimisation-only miscompilation would not be caught here.

### Why an executable instead of XCTest

At bootstrap the machine had only the Command Line Tools, which did not include
XCTest. Rather than add a dependency or a second toolchain, the suite became a
plain executable that the repo can run anywhere Swift runs, with the exit code as
the verdict and `check` as the only machinery.

The tradeoffs are deliberate:

- **First failure wins.** No per-test isolation, no skip, no filter, no parallel
  run. At roughly one second for the whole suite, a failed run still costs less
  than the build that precedes it.
- **No shared fixtures.** Each scenario constructs its own
  [`Game.swift`](../../Sources/SpaceInvadersCore/Game.swift) — each scenario
  constructs its own `SpaceInvadersGame`, so one scenario cannot leave state
  behind for the next.
- **Headless.** The core imports Foundation only, so the suite needs no GPU,
  window, or audio device.

### Why the file is ordered the way it is

Cheap structural facts come first — playfield size, 55 invaders, four bunkers,
initial lives — then one scenario per mechanism: movement, firing, bunker
damage, pause, mystery ship, death, game over. Each block builds a fresh game,
drives the public commands, and asserts on public read-only state.

After the scenarios comes the 60-second soak, which steers randomly from
[`Math.swift`](../../Sources/SpaceInvadersCore/Math.swift) — `SplitMix64` — and
asserts invariants every tick. It is last because it is the longest and the only
block whose failure could be a flake in the *harness* rather than the game.

Two details worth knowing:

- **The first `print` is not the end.** The suite prints `PASS: <count> checks`
  before the wave-clear autopilot, then prints a second line with the final
  count. Both must appear; a failure anywhere exits before its print.
- **The count is executions, not call sites.** There are about 66 `check(...)`
  call sites, but 23,116 executions, because `check` is called inside the soak's
  3,600-tick update loop. Roughly 23,000 of the count come from that one loop.

### Why not at app launch

The game is verified by launching it; the core is verified by the checks. Running
the suite inside `SpaceInvadersArcade` would delay startup, ship assertion code
in the release bundle, and give a headless simulation a dependency on a GUI
process. The separate executable keeps that boundary intact, as described in
[`AGENTS.md`](../../AGENTS.md#testing-standard).

### Reproducing it

```bash
swift run SpaceInvadersChecks      # debug build, full suite
time swift run SpaceInvadersChecks # about 1.1 s wall on the reference machine
make check                         # the whole gate, in stage order
```

Expected tail:

```text
PASS: 23109 checks
PASS: 23116 checks (including wave-clear autopilot)
```

A failure prints `FAIL: <message>` and exits 1 immediately; the message names the
invariant, so no stack trace or test name is needed to locate it.
