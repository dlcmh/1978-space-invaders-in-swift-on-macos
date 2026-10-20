# Is Metal used for all computations?

- **Project:** SPACE INVADERS — Metal Arcade
- **Recorded:** 2026-10-20 (+08:00, Asia/Kuala_Lumpur)
- **Last updated:** 2026-10-20

**No.** Metal is used only to draw the frame. Formation logic, projectile
physics, bunker damage, scoring, timers, and wave transitions run in plain Swift
on the CPU. Audio, windowing, input, and persistence use AVFoundation, AppKit,
and `UserDefaults`.

| Layer | Technology | What it does |
| --- | --- | --- |
| Simulation | Swift + Foundation, CPU | Game rules and state in `SpaceInvadersCore` |
| Frame scheduling | AppKit / QuartzCore, CPU | `MTKView` callback and fixed-step accumulator |
| Geometry | Swift, CPU | Builds the frame's triangles in `Canvas` |
| Rasterisation | **Metal, GPU** | Transforms vertices, rasterises, blends, resolves MSAA |
| Audio | AVFoundation, CPU | Synthesises PCM buffers, then plays them |
| Input and persistence | AppKit + `UserDefaults` | Keyboard, window, high score, mute |

### Where the split happens

[`Game.swift`](../../Sources/SpaceInvadersCore/Game.swift) — `update` owns the
whole simulation. The core imports only `Foundation`.

[`GameView.swift`](../../Sources/SpaceInvadersArcade/GameView.swift) — `draw(in:)`
runs the fixed-step loop and processes events before asking the renderer to
draw. `Renderer.render` receives a `SpaceInvadersGame` and only reads it.

[`Canvas.swift`](../../Sources/SpaceInvadersArcade/Canvas.swift) — `Canvas`
expands every star, invader pixel, bunker cell, bullet, glyph, panel, and
scanline into triangles. This is CPU work.

[`Renderer.swift`](../../Sources/SpaceInvadersArcade/Renderer.swift) — `render`
sets up one render pass, copies the vertex array into one of three rotating
buffers, and submits one `drawPrimitives` call for the entire frame.

[`MetalShaders.swift`](../../Sources/SpaceInvadersArcade/MetalShaders.swift) —
`MetalShaderSource` contains the whole GPU program. The vertex shader applies a
uniform scale and offset, converts the design-space position to clip space, and
passes the vertex colour through. The fragment shader returns that colour. There
is no lighting, simulation, or compute kernel.

[`SoundEngine.swift`](../../Sources/SpaceInvadersArcade/SoundEngine.swift) —
`makeBuffer` synthesises every effect sample-by-sample into
`AVAudioPCMBuffer`s with ordinary CPU code.

### Why this split

- The checks can import the core on a machine with no drawable.
- Rendering cannot change a ghost's decision or a bomb's timing.
- The renderer is stateless between frames except for reusable vertex buffers.
- Bug hunting is simpler: a wrong position is a simulation bug; a wrong colour
  is a presentation bug.

### Single draw call and MSAA

`Renderer` creates one pipeline whose vertex layout is `packed_float2` position
plus `packed_float4` colour. The 2D camera is passed as `Uniforms` through
`setVertexBytes`. All primitives are triangles, so the GPU can draw the frame in
one call after the CPU has sorted them into a single vertex array.

The `MTKView` requests 4× MSAA when the device supports it; the pipeline's
`rasterSampleCount` matches. Blending is standard source-alpha over
one-minus-source-alpha, which is what gives the glow layers and CRT scanlines
their soft look.

For a ground-up explanation of these terms, see the
[Metal crash course](../METAL_CRASH_COURSE.md).
