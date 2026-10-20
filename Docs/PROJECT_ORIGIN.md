# Project Origin and Decision Record

This document preserves the request that created SPACE INVADERS — Metal Arcade
and records the decisions that shaped the delivered v1.0. It is a historical and
governance document. The **Original request** block below is immutable.

- **Project:** SPACE INVADERS — Metal Arcade
- **Repository:** <https://github.com/dlcmh/1978-space-invaders-in-swift-on-macos>
- **Commissioned by:** David Chin ([@dlcmh](https://github.com/dlcmh))
- **Commissioned:** 2026-10-20 15:27:30 (+08:00, Asia/Kuala_Lumpur)
- **Delivery agent:** DeepSeek Harness (deepseek-flash)
- **Initial implementation commit:** recorded in the repository history
- **Initial public version:** 1.0

## Original request

The following is the human-authored request verbatim. Harness-supplied runtime
metadata that followed it is summarized separately and is not part of the
quote.

```text
reckon you can one-shot this game in clean Swift with Metal? Game description: "The original Space Invaders is a landmark fixed-shooter arcade game developed by Japanese designer Tomohiro Nishikado and released by Taito in 1978.

Key Details

• Developer & Designer: Tomohiro Nishikado
• Release Year: 1978 (released in Japan by Taito and distributed overseas by Midway Games)
• Genre: Fixed shooter / Shoot 'em up
• Core Gameplay:
	• Players control a horizontal laser cannon at the bottom of the screen to shoot descending waves of 55 alien ships.
	• The aliens move side-to-side in a zig-zag pattern and step closer to the bottom with each pass.
	• Four destructible defense bunkers provide temporary cover from enemy fire.
	• As you destroy more aliens, the remaining ships speed up (originally caused by processor load decreasing as sprites were cleared).
	• A bonus "Mystery Ship" occasionally crosses the top of the screen for extra points."

Do use /Users/dlcmh/dev/pac-man-arcade-swift-macos as a reference for how i'd like this repo and game artifacts to be shaped, developed and governed

set this repo's upstream to https://github.com/dlcmh/1978-space-invaders-in-swift-on-macos.git
```

## Runtime context at commissioning

- Workspace: `/Users/dlcmh/dev/1978-space-invaders-in-swift-on-macos`
- Host platform: macOS 26 on Apple silicon, Swift 6.3.3 toolchain
- Interaction surface: DeepSeek Harness Web GUI
- File policy: full local file access
- Repository state at commissioning: empty local directory; no Git repository

These facts explain implementation choices and are not ongoing requirements.

## Requirements captured from the request

1. Deliver a playable, original-style Space Invaders arcade game in **clean
   Swift** with **Metal** rendering, in one implementation pass.
2. Implement the canonical loop: a horizontal cannon at the bottom, 55 alien
   ships in five rows, side-to-side marching, and a step downward per pass.
3. Make the remaining invaders **speed up as their numbers fall**, in homage to
   the original hardware's decreasing processor load.
4. Include **four destructible defence bunkers** that provide temporary cover.
5. Include the bonus **Mystery Ship** crossing the top of the screen for extra
   points.
6. Shape the repository, development workflow, artifacts, and governance after
   `/Users/dlcmh/dev/pac-man-arcade-swift-macos`.
7. Set the repository's upstream to
   <https://github.com/dlcmh/1978-space-invaders-in-swift-on-macos.git>.

The historical details in the brief were treated as context and design intent.
No external arcade assets, ROM data, or online versions were used.

## Delivered implementation

- Native macOS app built with Swift Package Manager, AppKit, MetalKit, Metal,
  and AVFoundation.
- A headless `SpaceInvadersCore` simulation with a 224 × 256 playfield, 55
  invaders in five rows, the stepped formation, acceleration, one-shot cannon,
  enemy bombs, mystery ship, four destructible bunkers, waves, lives, score,
  high score, and deterministic randomness.
- A single-draw-call Metal renderer with 4× MSAA, original pixel-art invaders,
  cannon, mystery ship, destructible shield cells, procedural starfield,
  cabinet frame, pixel font, HUD, overlays, and CRT scanlines.
- Procedural chiptune audio, including the four-note marching bass loop, shot,
  impact, death, mystery-ship, extra-life, wave-clear, and game-over cues.
- Standalone simulation checks using only the public game API, including a
  wave-clear autopilot and a 60-second movement soak test.
- Governance documents, a Metal crash course, source-grounded Q&A, a
  refactoring record, ad-hoc-signed app packaging, and DMG tooling.
- The canonical remote is `origin`, and `main` tracks `origin/main`.

## Explicit scope decisions

| Topic | Decision |
| --- | --- |
| Platform | Native macOS; no browser/WebAssembly build in v1.0. |
| Assets | No original arcade sprites, ROM data, fonts, or audio. Everything is procedural. |
| Formation | One deterministic formation step every interval, rather than 55 asynchronous per-invader updates. |
| Speed-up | Modeled explicitly from the number of surviving invaders and the wave number. |
| Bunkers | 22 × 16 cell grids with radial chipping; restored at the start of each wave. |
| Mystery ship | Crosses above the formation; value chosen deterministically from 50/100/150/300. |
| Extra life | At 1,000 points, then every 5,000 points. |
| Two-player mode | Out of scope for v1.0. |
| Network | The game is fully offline. No leaderboards, telemetry, or downloads. |
| Persistence | Local `UserDefaults` only (high score and mute preference). |
| Licensing | No open-source license selected. All rights remain with the owner/contributors; see [GOVERNANCE.md](../GOVERNANCE.md). |
| Trademark | Unofficial fan tribute; not affiliated with or endorsed by Taito or Midway. |

## Verification record

The v1.0 baseline was built, checked, and launched on the commissioning host.
The simulation check suite passed **23,116 checks**, covering:

- playfield dimensions, the 55-invader formation, species counts, and points;
- cannon rail limits, continuous movement, firing, and the one-shot rule;
- player-shot collision, score, high score, and explosion effects;
- destructible bunker damage;
- pause and resume behavior;
- mystery-ship appearance, valid value, and departure;
- a 60-second movement soak test;
- bomb collision, life loss, and game-over/restart transitions; and
- a wave-clear autopilot that destroys all 55 invaders, advances to wave 2,
  and verifies that the new formation and bunkers are restored.

Visual verification used window captures recorded in [Docs/](../Docs/). The
screenshots in this repository were captured from the signed app bundle at the
default 720 × 900 window size.

## Governance directive

The governance baseline was requested as part of the original commission: use
the Pac-Man repository as the model for repository shape, artifacts,
development, and governance, and set the new repository's upstream. This
established [AGENTS.md](../AGENTS.md), [CONTRIBUTING.md](../CONTRIBUTING.md),
[GOVERNANCE.md](../GOVERNANCE.md), [SECURITY.md](../SECURITY.md), and this
record.

## Record maintenance

- Do not edit the **Original request** quotation.
- Append material decisions rather than silently rewriting history.
- Update the verification section when the release baseline changes.
- Changes to governance itself follow [GOVERNANCE.md](../GOVERNANCE.md).
