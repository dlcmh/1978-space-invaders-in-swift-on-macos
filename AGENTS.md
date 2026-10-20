# AGENTS.md

Operating instructions for AI coding agents working in this repository. These
rules are mandatory unless the maintainer gives a direct instruction that
supersedes them. Update this file when project policy changes.

- **Project:** SPACE INVADERS — Metal Arcade
- **Canonical repository:** <https://github.com/dlcmh/1978-space-invaders-in-swift-on-macos>
- **Maintainer:** [@dlcmh](https://github.com/dlcmh)
- **Governance baseline:** 2026-10-20
- **Current release:** 1.0

## Read first

1. [Docs/PROJECT_ORIGIN.md](Docs/PROJECT_ORIGIN.md) — why this project exists,
   including the original request. Its quoted request is a historical record
   and must not be edited.
2. [GOVERNANCE.md](GOVERNANCE.md) — decision-making, releases, licensing, and
   amendment rules.
3. [CONTRIBUTING.md](CONTRIBUTING.md) — build, test, and contribution workflow.
4. [SECURITY.md](SECURITY.md) — vulnerability reporting and privacy posture.

## Project layout

| Path | Responsibility |
| --- | --- |
| `Sources/SpaceInvadersCore/` | Pure Swift simulation. Foundation only; no AppKit, Metal, or audio imports. |
| `Sources/SpaceInvadersArcade/` | macOS app, Metal renderer, input, procedural audio, and persistence. |
| `Checks/` | Dependency-free simulation checks executable. |
| `Resources/` | App metadata and generated icon files. |
| `Docs/` | Screenshots, project origin, Metal crash course, code Q&A under `Docs/QnA/`, and refactoring decision records under `Docs/Refactoring/`. |
| `scripts/` | Deterministic app-bundle packaging, icon generation, documentation link checking, and the `make check` gate. |
| `dist/` | Generated, git-ignored app and DMG artifacts. Never commit it. |

## Prerequisites

- macOS 13 or newer on a Metal-capable Mac.
- A Swift toolchain from Xcode or the Apple Command Line Tools.
- No third-party runtime dependencies, package managers, or network services.

The bootstrap environment used only the Command Line Tools and did not include
XCTest. This is why verification lives in the standalone `SpaceInvadersChecks`
executable instead of an XCTest target. Do not replace it with XCTest unless
you verify the toolchain first.

## Build, run, and verify

Run these from the repository root:

```bash
swift build                              # compile debug
swift run SpaceInvadersArcade            # launch the game
swift run SpaceInvadersChecks            # run the simulation checks
make app                                 # build the release app bundle
make dmg                                 # build dist/SPACE-INVADERS-1.0.dmg
make check                               # the full gate: lint, warnings-as-errors, checks, docs
make checks                              # alias for the checks executable
make docs-check                          # validate doc links and code references
```

`swift build` is necessary but not sufficient for rendering changes. The Metal
shader is compiled at runtime, so a successful build can still launch into an
error alert if the MSL is invalid. After touching shaders, renderer code,
windowing, input, or audio, launch the app and confirm it actually runs.

For repeatable presentation captures, `GameView` accepts three development
environment variables:

| Variable | Effect |
| --- | --- |
| `SPACEINVADERS_AUTOSTART=1` | Start a game immediately instead of showing attract mode. |
| `SPACEINVADERS_AUTOFIRE=1` | Fire every 0.65 s while playing, for screenshots and smoke tests. |
| `SPACEINVADERS_AUTOPAUSE=0` | Do not pause when the app loses focus while capturing. |

These are development aids, not gameplay features. Do not expose them in the
app's user-facing controls or documentation as player options.

## Non-negotiable architecture

1. **Keep simulation and presentation separate.** `SpaceInvadersCore` must
   remain headless and UI-framework-free so it can be exercised by
   `SpaceInvadersChecks` and future tools. Do not import AppKit, Metal,
   MetalKit, or AVFoundation there.
2. **Keep Metal.** Use the existing single-pass, immediate-mode triangle
   renderer and `MTKView`. Do not replace it with SpriteKit, SceneKit, Core
   Animation, or an external game engine.
3. **Keep assets procedural.** Invader art, cannon, mystery ship, bunkers,
   stars, font, icon, and audio are generated in code or by the documented icon
   script. Do not add ripped arcade sprites, ROM data, scans, or copyrighted
   audio.
4. **Keep the game offline.** No network calls, telemetry, analytics, remote
   configuration, or account systems. The only persisted state is local
   `UserDefaults`.
5. **No new dependencies** without explicit maintainer approval.
6. **Authoritative simulation is `SpaceInvadersGame`.** Do not duplicate
   gameplay rules in the renderer or app layer. Renderer state must be
   read-only.
7. **Keep the game loop deterministic and fixed-step.** The app runs simulation
   updates at 60 Hz with a bounded catch-up loop. Avoid frame-rate-dependent
   movement, timers, or random behavior. All randomness comes from
   `SplitMix64`.
8. **Preserve public read-only state.** Prefer `public private(set)` and
   explicit commands over mutable public fields. Checks must drive the public
   input API rather than test-only back doors.

## Gameplay invariants

Changes that affect the formation, projectiles, bunkers, or scoring must
preserve or deliberately update these known invariants and their checks:

- The playfield is 224 × 256 arcade pixels. The player cannon is 13 × 8 at
  y = 224 and moves between x = 8 and x = 203 on its rails.
- There are 55 invaders in five rows of eleven: 11 squid (30 points), 22 crabs
  (20 points), and 22 octopus (10 points). Each has two animation frames.
- The formation steps 2 pixels sideways. When any living invader would cross
  the 8-pixel side margin, every survivor drops 8 pixels and the direction
  reverses. A survivor reaching the invasion line at y = 216 ends the game.
- The march interval starts near 0.41 s on wave 1, shortens as invaders are
  destroyed, floors at 0.09 s, and shrinks further on later waves. Fewer
  invaders must always mean a shorter interval.
- The cannon may have only one shot in flight. The shot travels upward from
  the cannon at 340 px/s and is 1 × 5 pixels.
- Enemy bombs come from the lowest living invader in a randomly chosen column.
  At most three bombs are in flight. Bomb speed rises with the wave.
- Each of the four bunkers is a 22 × 16 grid of solid cells at y = 188, with
  322 cells in its initial shape. Hits remove a small radial bite with a little
  extra chipping; aliens erase every cell they overlap. A new wave restores
  all four to 322 cells.
- The mystery ship crosses at y = 30 at 38 px/s. It is worth 50, 100, 150, or
  300 points and leaves after crossing the screen.
- A bonus cannon is awarded at 1,000 points, then at every 5,000-point interval
  after that. A player starts with three cannons and the HUD shows the two
  reserve cannons.
- Clearing all 55 invaders enters `waveComplete`, then restores the formation
  and bunkers and starts wave 2 with a faster tempo.
- Death, ready, pause, wave-clear, and game-over transitions continue to work
  from the public API.

The fixed values above are asserted by `SpaceInvadersChecks`. If a design change
intentionally alters one, update the check and the documentation in the same
commit.

## Static checks

`make check` runs [`scripts/check.sh`](scripts/check.sh), the gate every change
must pass:

1. `xcrun swift-format lint --recursive Sources Checks` — style from
   [`.swift-format`](.swift-format) (4-space indent, 100 columns).
2. `swift build -c release -Xswiftc -warnings-as-errors` — unused variables,
   dead stores, unreachable code, and actor-isolation warnings.
3. `swift run SpaceInvadersChecks` — behavior.
4. `python3 scripts/check_docs.py` — documentation links and cited symbols.

Swift ships no Clippy equivalent, and this repository takes no third-party
dependencies, so the gate uses only `swift-format` and the compiler. Apply the
house style with `xcrun swift-format format --in-place --recursive Sources
Checks`. `Sources/SpaceInvadersArcade/MetalShaders.swift` opts out with
`// swift-format-ignore-file` because its payload is an MSL string literal that
the formatter would re-indent. Do not add SwiftLint, Periphery, or other
packages to get stronger analysis.

## Testing standard

`Checks/main.swift` is the regression suite. Add checks when changing gameplay,
movement, collision, scoring, bunkers, waves, or state transitions. The suite
intentionally uses only public game APIs.

A green run currently ends with:

```text
PASS: 23109 checks
PASS: 23116 checks (including wave-clear autopilot)
```

Counts may grow. The important requirement is that all checks pass. For pure
visual or packaging changes, also rebuild and open the resulting `.app`.

## Documentation and code references

A line number in prose is wrong the moment ten lines are inserted above it, and
nothing fails. Documentation therefore cites a **file and a symbol**, never a
line range:

```markdown
[`Game.swift`](Sources/SpaceInvadersCore/Game.swift) — `updateFormation`
```

- Link the file, then name the symbol in backticks on the same line or in the
  same sentence.
- Prefer the most specific symbol — a function, property, or type — over a
  general word such as a state name.
- Link Markdown by heading anchor
  (`../AGENTS.md#non-negotiable-architecture`), never by line.
- When a symbol is renamed or removed, update every document that cites it.

`make docs-check` enforces this: every relative link must resolve, every heading
anchor must exist, every cited symbol must still occur in the linked file, and
`#L` line anchors are rejected.

`make docs-impact` is the answer to "which docs does this code change touch?".
It lists the documents that reference files changed against `HEAD` (or
`--base <rev>`) and warns when the diff removes a symbol one of them cites.
Treat that list as the re-read queue after changing code, and fix any reference
the change invalidated.

`Docs/PROJECT_ORIGIN.md` is a historical record: its quotation is immutable, so
correct a stale reference there by annotating outside the quote rather than
rewriting it. A single line can opt out of the symbol rule with
`<!-- docs-check: ignore -->`.

## Git and release workflow

- `main` is the canonical trunk.
- Use Conventional Commit messages, for example:
  - `feat: add the mystery ship and scoring popup`
  - `fix: stop a bomb from skipping a chipped bunker cell`
  - `docs: record the formation acceleration model`
  - `chore: refresh application icon`
- Keep commits coherent and reviewable. Do not mix unrelated refactors with
  gameplay changes.
- Run `make check` before committing; it covers `swift build` and
  `swift run SpaceInvadersChecks`.
- Push to `origin/main`. The maintainer has authorized normal agent commits and
  pushes in this repository.
- Never force-push `main`, rewrite published history, or change remotes without
  explicit maintainer approval.
- Do not commit `.build/`, `dist/`, `.DS_Store`, or other generated artifacts.
  Distribution binaries belong in a release artifact, not source history.
- Do not tag or publish a GitHub Release unless the maintainer asks.

## Rendering and audio guidance

- Keep the presentation at the 896 × 1120 design resolution and letterbox it
  cleanly when the window aspect changes. The 224 × 256 playfield sits at
  y = 48 with a 4× pixel scale.
- Maintain 4× MSAA where supported and the existing triple-buffered vertex
  path.
- Respect the established neon palette, pixel font, score HUD, starfield,
  cabinet frame, and scanline look.
- Screenshots in `Docs/` are user-facing documentation. Refresh them when a
  material visual change invalidates them.
- Sound effects are synthesized at launch. Keep the mute setting persisted and
  do not introduce audio files or network-streamed audio.

## Persistence and privacy

The app stores only two local preferences:

| Key | Purpose |
| --- | --- |
| `SpaceInvadersArcadeHighScore` | Persistent local high score |
| `SpaceInvadersArcadeMuted` | Sound preference |

Do not add analytics, identifiers, crash uploaders, or remote persistence. If a
new stored preference is unavoidable, document it here and in `SECURITY.md`.

## Legal and licensing

- SPACE INVADERS is a trademark of TAITO CORPORATION. This is an unofficial fan
  tribute and must never be presented as affiliated with or endorsed by Taito
  or Midway.
- No open-source license has been selected for this repository. Do not add a
  license, relicense code, or claim reuse rights without explicit maintainer
  approval.
- Only contribute original code and generated art/audio, or material whose
  license is compatible and documented.

## Agent operating protocol

1. Read `AGENTS.md`, the origin record, and the relevant source before editing.
2. Inspect `git status` and preserve unrelated local work.
3. Make the smallest coherent change that satisfies the request.
4. Add or update checks for behavioral changes.
5. Build, run `make check`, and launch the app for presentation changes.
6. Update README/governance docs when behavior, controls, build steps, or
   policy changes, then run `make docs-check` and resolve the docs listed by
   `make docs-impact`.
7. Commit with a Conventional Commit message and push to `origin/main` when
   authorized.
8. Report what changed, what was verified, and any remaining risks or follow-up
   work.

Do not claim to have run something you did not run. If the environment prevents
a verification step, say exactly what was blocked.

## Definition of done

- [ ] `make check` passes: lint, warnings-as-errors build, checks, and docs.
- [ ] `swift run SpaceInvadersChecks` passes.
- [ ] `make docs-check` passes, and docs listed by `make docs-impact` were
      re-read after code changes.
- [ ] The app launches and renders correctly when presentation changed.
- [ ] Gameplay/controls documentation is current.
- [ ] Governance and origin records remain accurate.
- [ ] No generated binaries or secrets are staged.
- [ ] Change is committed and pushed, if authorized.

## When to stop and ask the maintainer

Ask before:

- changing licensing, repository visibility, or the canonical remote;
- adding third-party dependencies, assets, telemetry, or network access;
- making incompatible gameplay changes or altering the canonical playfield;
- cutting a release, tag, or public distribution build;
- force-pushing or rewriting published history; or
- implementing large optional scope such as a two-player cabinet mode.
