# How do I tell whether the game's CPU and memory use is acceptable?

- **Project:** SPACE INVADERS — Metal Arcade
- **Recorded:** 2026-10-20 (+08:00, Asia/Kuala_Lumpur)
- **Last updated:** 2026-10-20

A number like "29% CPU and 152 MB" is not a verdict on its own. It is a verdict
once you know three things: how the number relates to the 60 Hz frame budget,
what is actually holding the memory, and whether either value drifts over time.
For this game the short answer is that 29% and 152 MB look *normal*, and here is
how to confirm that on your machine rather than trusting the claim.

### 1. Convert CPU percentage into milliseconds per frame

macOS reports CPU per core: 100% means one core fully busy, and a threaded
process can exceed 100%. The game is pinned to 60 frames per second, so one
frame's budget is 1 / 60 s = **16.67 ms**.

    ms of CPU per frame = CPU% / 100 × 16.67

| Reported CPU | CPU per frame | Share of the 16.67 ms budget |
| --- | --- | --- |
| 10% | 1.7 ms | 10% |
| 29% | 4.8 ms | 29% |
| 60% | 10.0 ms | 60% |
| 100% | 16.7 ms | 100% — no headroom left |

At 29% the process spends about 4.8 ms of every 16.67 ms doing work and the rest
waiting for the display. That is roughly a 3.5× margin before it can no longer
hold 60 fps. When CPU per frame reaches the budget, the frame rate is the first
thing to drop — that is the real "not ok" threshold, not an absolute percentage.

Two measurement traps:

- **Debug builds.** `swift run SpaceInvadersArcade` compiles without
  optimisation. Always measure `-c release` (or the packaged `.app`) before
  comparing numbers.
- **The parent process.** `swift run` spawns the game as a child, so a process
  list sorted by CPU may be showing `swift-run`, not the game. Match the child
  with `pgrep -f SpaceInvadersArcade` and measure that PID.

Also note that `ps -o %cpu` is an average since launch, while `top` reports a
recent interval. Let the app run for half a minute before reading either.

### 2. Check the number against what the loop necessarily does

[`GameView.swift`](../../Sources/SpaceInvadersArcade/GameView.swift) — `draw(in:)`
runs on the main thread and always renders, then runs at most eight fixed
`update(dt:)` steps. `preferredFramesPerSecond` is 60 and `isPaused` stays
`false`, so the view requests a frame whether the game is playing, paused, or
sitting in attract mode.

[`Game.swift`](../../Sources/SpaceInvadersCore/Game.swift) — `update(dt:)`
returns immediately when `isPaused` is set, and `.attract`/`.gameOver` only
advance timers. Simulation cost therefore collapses outside gameplay while
rendering cost does not.

That asymmetry matters when judging CPU: most of the 29% is the cost of drawing
a frame, not the cost of the invasion. Pausing the game and seeing CPU stay
close to its playing value is expected, not a bug.

[`Canvas.swift`](../../Sources/SpaceInvadersArcade/Canvas.swift) — `reset` and
the `add*` methods rebuild every triangle for the frame on the CPU: 55 sprites,
up to 1,288 bunker cells, scanlines, HUD glyphs, and stars.

[`Renderer.swift`](../../Sources/SpaceInvadersArcade/Renderer.swift) — `render`
copies that vertex array into the current buffer and submits one
`drawPrimitives` call, gated by `inFlightSemaphore` with three buffers. The cost
is proportional to vertices, so it is flat across waves and phases.

[`SoundEngine.swift`](../../Sources/SpaceInvadersArcade/SoundEngine.swift) —
`makeBuffer` synthesises each effect once at launch, and `players` keeps ten
`AVAudioPlayerNode`s running. Idle audio costs a render thread, not per-shot
synthesis.

If CPU is high, `sample <pid> 10 -file /tmp/si.txt` should show the hot frames
inside `Canvas` and `Renderer.render`. Time spent anywhere else — a font rebuilt
per frame, a `UserDefaults` write in the draw path, allocation churn — is the
signal that something is wrong rather than merely expensive.

### 3. Break memory down before calling it large

Memory here is dominated by screen-sized Metal textures, not by game state.
`footprint <pid>` and `vmmap -summary <pid>` label the regions; on a 720 × 900
point window on a 2× display the arithmetic is:

| Consumer | Size | Where it comes from |
| --- | --- | --- |
| 3 drawables | 31 MB | 1440 × 1800 px × 4 B ≈ 10.4 MB each |
| 4× MSAA colour target | 41 MB | the same surface again, × 4 samples |
| 3 vertex buffers | 11.5 MB | 160,000 vertices × 6 floats × 4 B |
| Canvas array | 3.4 MB | 140,000 vertices reserved |
| Audio buffers and engine | ~2 MB | ten players plus synthesised PCM |
| Frameworks, heap, stacks | ~40 MB | AppKit, Metal, AVFoundation, runtime |

That is roughly 130–150 MB, which is where a 152 MB reading comes from. The two
graphics regions are visible in `vmmap` as `IOSurface` (the drawables) and
`owned unmapped (graphics)` (the MSAA target).

[`GameView.swift`](../../Sources/SpaceInvadersArcade/GameView.swift) — `init`
sets `sampleCount` to 4 when the device supports it and `preferredFramesPerSecond`
to 60, which fixes the MSAA multiplier.

[`AppDelegate.swift`](../../Sources/SpaceInvadersArcade/AppDelegate.swift) —
`createWindow` starts at 720 × 900 and keeps `contentAspectRatio` locked to the
design size; enlarging the window enlarges the drawables.

[`Renderer.swift`](../../Sources/SpaceInvadersArcade/Renderer.swift) —
`vertexBuffers` allocates three buffers and grows one by doubling if a frame
ever exceeds it. Normal play does not approach that ceiling, so vertex memory is
steady rather than creeping.

The practical consequence: **memory scales with window pixels, not with waves or
play time.** Resizing to a 4K-sized window quadruples the drawable and MSAA
lines. If you want a budget, compute it as

    bytes ≈ pixels × 4 × (3 drawables + sampleCount) + ~20 MB

and treat the result as the floor, not a leak.

One more trap: `ps` RSS and Activity Monitor's Memory column disagree (85 MB vs
145 MB on the same process here) because RSS counts shared framework pages.
`footprint` reports `phys_footprint`, which is what Activity Monitor shows — use
one tool consistently when comparing readings.

### 4. Run the three tests that actually decide

**a. Is it steady?** Launch, play for ten minutes, and compare
`phys_footprint` against `phys_footprint_peak`. They should be within a few MB.
Rising footprint with a flat workload is a leak; ignore the absolute number
until this passes.

**b. Does it scale as predicted?** Resize the window larger and smaller. Graphics
memory should track pixel count and return when the window returns. Memory that
does not come back after shrinking points at retained textures or buffers.

**c. Does the frame rate hold?** Record a Metal System Trace in Instruments, or
watch for stutter while playing. The fixed-step loop catches up in at most eight
updates, so a sustained shortfall shows up as visible jumps rather than a slowly
falling frame counter. CPU near 100% of one core *and* dropped frames is the
combination that means "too expensive". CPU at 29% with smooth play does not.

### 5. Judge energy separately from CPU

A 60 Hz Metal game keeps the GPU and display pipeline busy, so it draws more
power than an idle text editor and less than a 3D title. On a laptop, "acceptable"
depends on whether it is plugged in and whether the fan stays quiet. The
low-noise checks are Activity Monitor's Energy tab and, with `sudo`,
`powermetrics --samplers cpu_power,gpu_power -i 1000`. Neither is a correctness
gate; they are the numbers to quote when the question is battery life rather
than performance.

### 6. Reproduce the measurement

```bash
swift build -c release
SPACEINVADERS_AUTOSTART=1 .build/release/SpaceInvadersArcade &
PID=$(pgrep -f 'SpaceInvadersArcade$' | head -1)

ps -o pid,%cpu,rss,time -p "$PID"     # lifetime average
top -l 5 -s 1 -pid "$PID" -stats pid,cpu,mem   # recent samples
footprint "$PID"                      # phys_footprint, the Activity Monitor number
vmmap -summary "$PID" | head -40      # IOSurface / graphics / malloc split
sample "$PID" 10 -file /tmp/si.txt    # where the CPU time goes
```

Run it once in attract mode and once while playing. Attract mode draws fewer
sprites because the title panel hides the formation and shields, so compare the
readings knowing its presentation cost is lower; a large gap beyond that means
simulation, not presentation, is the cost.

### Bottom line

- 29% CPU at 60 fps is about 4.8 ms of a 16.67 ms frame: comfortable headroom,
  and *expected* for a per-frame CPU-built vertex stream plus a 4× MSAA pass.
- 152 MB is three window-sized drawables plus their 4× MSAA target plus about
  20 MB of buffers and runtime — it moves with window size, not with game state.
- The values are acceptable as long as footprint is flat over time, memory
  returns when the window shrinks, and frames stay smooth. Absolute numbers
  without those three checks say very little.
