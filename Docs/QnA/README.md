# Q&A

Questions about how **SPACE INVADERS — Metal Arcade** works, with answers
grounded in the source. Each entry is a standalone document named after the
question and cites the files and symbols that implement the behavior, so the
references survive unrelated edits.

Documents are listed newest first, by the **Last updated** date recorded in each
file. When dates are equal, the most recently added question comes first.

| Question | Last updated | Covers |
| --- | --- | --- |
| [When does the check suite run, and why then?](when-the-check-suite-runs.md) | 2026-10-20 | Top-level execution in the checks executable, the gate's four stages, first-failure semantics, and why it is not XCTest |
| [What do "simulation" and "presentation" mean?](simulation-and-presentation.md) | 2026-10-20 | The two halves, what each owns, the one-way command and event arrows, ambiguous cases, and how to classify a change |
| [How do I tell whether the game's CPU and memory use is acceptable?](judging-cpu-and-memory-use.md) | 2026-10-20 | The 60 Hz frame budget, why rendering dominates CPU, what holds the 150 MB, and the stability, scaling, and frame-rate checks that decide it |
| [How is SpaceInvadersCore structured, and why is the simulation headless?](spaceinvaderscore-architecture.md) | 2026-10-20 | The core/presentation boundary, commands, read-only state, phases, and deterministic RNG |
| [How does the invader formation march, and why does it speed up?](invader-march-and-acceleration.md) | 2026-10-20 | Formation stepping, edge drops, the acceleration formula, and wave tempo |
| [How do the four bunkers take damage?](destructible-bunkers.md) | 2026-10-20 | Cell grids, projectile impacts, invader erosion, and wave restoration |
| [Is Metal used for all computations?](metal-rendering-split.md) | 2026-10-20 | The CPU-simulation / GPU-rendering split, single draw call, blending, and MSAA |
| [How do the mystery ship, bombs, and scoring work?](mystery-ship-bombs-and-scoring.md) | 2026-10-20 | Spawn timing, target selection, point values, extra lives, and the score HUD |

## Adding an entry

1. Name the file after the question, not the date
   (`invader-march-and-acceleration.md`), so links survive re-edits.
2. Start the document with the question as its `#` heading, then record both a
   `Recorded` and a `Last updated` date in the metadata block, matching the
   style of the existing entries.
3. Insert the document into the table above in descending date order.
4. Cite code by file and symbol, never by line number, and run `make docs-check`
   before committing. The convention is defined in
   [`AGENTS.md`](../../AGENTS.md#documentation-and-code-references).

To confirm the date to record, use the commit that last touched the file:

```bash
git log -1 --format=%cs -- Docs/QnA/<file>.md
```

The in-file date is authoritative because it survives cloning, where file
modification times do not. The two should agree with the command above.
