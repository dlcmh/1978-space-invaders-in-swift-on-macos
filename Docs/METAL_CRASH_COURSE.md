# A Metal crash course, using SPACE INVADERS as the textbook

This document is for someone who has never written a GPU API. It starts with
what the GPU is actually doing, then follows one frame of this game from the
simulation to the screen. Every concept is tied to a real symbol in this
repository. No prior graphics knowledge is assumed; a little familiarity with
web rendering or canvas APIs helps.

If you only remember one thing: **the GPU here is a very fast triangle
painter.** It does not know what an invader is, where a bomb is, or what a
bunker is. Swift decides all of that, turns the result into triangles, and asks
Metal to paint them.

## 1. The mental model

Imagine an enormous spreadsheet of pixels. The CPU (Swift) prepares a list of
triangles with a colour per vertex. The GPU (Metal) takes that list, transforms
the triangle corners into screen positions, fills the pixels, and blends the
result into the drawable.

The game's entire visual vocabulary is triangles:

- a star is a tiny rectangle = two triangles;
- an invader pixel is a rectangle = two triangles;
- a bunker cell is a rectangle = two triangles;
- a glowing circle is a fan of triangles;
- a scanline is a rectangle;
- a panel is a rectangle plus four line quads.

[`Canvas.swift`](../Sources/SpaceInvadersArcade/Canvas.swift) — `Canvas` is
the CPU-side triangle factory. Its `addRect`, `addCircle`, `addLine`, and
`addQuad` methods all funnel into `addTriangle`, which appends six floats per
vertex: `x`, `y`, `r`, `g`, `b`, `a`.

This is called **immediate-mode** geometry: every frame builds a fresh vertex
array from scratch. There is no retained scene graph, no node tree, and no
per-object draw call.

## 2. The coordinate spaces

There are three coordinate spaces in the renderer, and confusing them is the
most common source of "why is my triangle off-screen?" bugs.

### World space

The simulation lives in **224 × 256 arcade pixels**. The origin is the top-left
of the CRT. An invader at world `(40, 44)` is 40 pixels from the left and 44
from the top. This is the same space the original cabinet used.

[`Arena.swift`](../Sources/SpaceInvadersCore/Arena.swift) — `Arena` defines
`width = 224`, `height = 256`, the player rails, the bunker row, and the
invasion line.

### Screen space

The renderer draws into a **896 × 1120 design canvas**: the playfield is scaled
4× and sits at `y = 48`, leaving a 48-pixel status strip at the top and a
48-pixel control strip at the bottom. All pixel-art rectangles are four screen
pixels wide.

[`Renderer.swift`](../Sources/SpaceInvadersArcade/Renderer.swift) —
`playfieldOrigin` and `unit` define this mapping. `screenPoint` and
`screenRect` convert world coordinates to screen coordinates.

### Clip space

Metal's vertex shader must return positions in **normalized device
coordinates** (NDC): x and y in `[-1, 1]`, with y pointing up. The renderer's
shader receives the drawable's pixel size, a uniform scale, and a letterbox
offset. It computes:

```text
screen = world × scale + offset
ndc.x  = (screen.x / viewportWidth)  × 2 − 1
ndc.y  = 1 − (screen.y / viewportHeight) × 2
```

The `1 −` flips y because screen space grows downward and NDC grows upward.
[`MetalShaders.swift`](../Sources/SpaceInvadersArcade/MetalShaders.swift) —
`MetalShaderSource` is the string that contains that arithmetic.

## 3. The vertex

A vertex is the smallest thing the GPU understands. This project uses six
floats: position and RGBA colour.

```
struct VertexIn {
    packed_float2 position;   // screen-space x, y
    packed_float4 color;      // r, g, b, a in 0...1
};
```

`packed_float2` and `packed_float4` mean tightly packed, not SIMD-aligned. The
CPU side matches that layout in
[`Canvas.swift`](../Sources/SpaceInvadersArcade/Canvas.swift) — `floatsPerVertex`
is 6, and `addVertex` appends the six floats in the same order. If these two
layouts disagree, you get garbage triangles that look like a graphics driver
bug.

The vertex shader turns `VertexIn` into `VertexOut`:

```metal
vertex VertexOut vertex_main(const device VertexIn *vertices [[buffer(0)]],
                             constant Uniforms &uniforms [[buffer(1)]],
                             uint vertexID [[vertex_id]]) {
    VertexIn input = vertices[vertexID];
    float2 screenPosition = float2(input.position) * uniforms.scale + uniforms.offset;
    float2 ndc = float2((screenPosition.x / uniforms.viewportSize.x) * 2.0 - 1.0,
                        1.0 - (screenPosition.y / uniforms.viewportSize.y) * 2.0);
    VertexOut out;
    out.position = float4(ndc, 0.0, 1.0);
    out.color = float4(input.color);
    return out;
}
```

`[[buffer(0)]]` is the vertex buffer, `[[buffer(1)]]` is a small block of
uniforms, and `[[vertex_id]]` is the GPU's index into the vertex array.

## 4. The uniforms

Uniforms are values that stay constant for an entire draw call. This game has
only three:

- `viewportSize` — the drawable's pixel dimensions;
- `scale` — the letterbox scale factor;
- `offset` — the letterbox offset.

[`Renderer.swift`](../Sources/SpaceInvadersArcade/Renderer.swift) — `render`
computes them from `view.drawableSize` and uploads them with
`setVertexBytes`. Because the design is portrait, the scale is
`min(drawableWidth / 896, drawableHeight / 1120)`, which letterboxes cleanly at
any window size.

## 5. The fragment

The fragment shader runs once per covered pixel (or sample, with MSAA). It
receives the interpolated colour from the vertex shader and returns it:

```metal
fragment float4 fragment_main(VertexOut in [[stage_in]]) {
    return in.color;
}
```

There is no texture sampling, no lighting, and no noise. Every visual effect is
geometry and alpha. The CRT scanlines are a stack of translucent rectangles; the
glows are circles with low alpha; the score font is a set of coloured cells.

[`PixelFont.swift`](../Sources/SpaceInvadersArcade/PixelFont.swift) — `draw`
turns a 5 × 7 glyph bitmap into rectangles, one per lit pixel. That is why the
font stays crisp at any window size and needs no font file.

## 6. One draw call

A naïve 2D game might issue a draw call per sprite. This one issues **one** call
for the entire frame. The recipe:

1. Reset the CPU vertex array.
2. Append all triangles for the backdrop, stars, bunkers, aliens, UFO, bullets,
   player, explosions, HUD, overlays, and scanlines.
3. Copy the array into a Metal buffer.
4. Set the pipeline, vertex buffer, and uniforms.
5. Call `drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: n)`.

[`Renderer.swift`](../Sources/SpaceInvadersArcade/Renderer.swift) — `render`
performs all five steps. `Canvas.vertexCount` is `vertices.count / 6`.

Why bother? Every draw call has CPU overhead and can force the GPU to switch
state. One call keeps the frame cheap and the code easy to reason about. The
tradeoff is that every object must be a triangle, and the CPU must rebuild the
list each frame. At a few tens of thousands of triangles, that is a good trade.

## 7. Buffers and triple buffering

The GPU may still be reading last frame's buffer while the CPU is filling this
frame's. Writing into the same memory would tear the image.

The renderer keeps **three** shared buffers and rotates through them with
`frameIndex`. A `DispatchSemaphore(value: 3)` prevents the CPU from getting more
than three frames ahead. A command-buffer completion handler signals the
semaphore when the GPU is done.

[`Renderer.swift`](../Sources/SpaceInvadersArcade/Renderer.swift) — `render`
shows the wait, the buffer growth check, the `copyMemory` upload, and the
completion handler.

When the vertex array outgrows a buffer, the renderer allocates a larger one
rather than crashing. That is why the initial capacity is a comfortable reserve,
not a hard limit.

## 8. Blending

Alpha blending is what makes the glows and scanlines work. The pipeline uses:

- source RGB factor: `sourceAlpha`;
- destination RGB factor: `oneMinusSourceAlpha`;
- add operation.

So a white rectangle with alpha 0.05 over deep navy produces a faint grey-blue
wash, not an opaque white block. The order of drawing matters: the backdrop
comes first, then stars, then objects, then overlays, then scanlines.

[`Renderer.swift`](../Sources/SpaceInvadersArcade/Renderer.swift) — `render`
creates the pipeline and enables blending in the `MTLRenderPipelineDescriptor`.

## 9. MSAA

MSAA stands for multisample anti-aliasing. Instead of one colour sample per
pixel at the pixel centre, the GPU takes several samples and resolves them. It
smooths the edges of triangles without changing the geometry.

This project requests 4× MSAA when the device supports it, and falls back to
1× otherwise. The view's `sampleCount` and the pipeline's
`rasterSampleCount` must match.

[`GameView.swift`](../Sources/SpaceInvadersArcade/GameView.swift) — `init`
sets `sampleCount` from `device.supportsTextureSampleCount(4)`.

[`Renderer.swift`](../Sources/SpaceInvadersArcade/Renderer.swift) — `init`
copies `view.sampleCount` into the pipeline descriptor.

## 10. The frame lifecycle

Putting it together, one frame looks like this:

1. `MTKView` calls `GameView.draw(in:)` at up to 60 Hz.
2. The accumulator runs zero or more fixed 1/60 s simulation steps.
3. Events drain into the sound engine.
4. `Renderer.render` resets `Canvas`.
5. Draw functions append triangles in back-to-front order.
6. The vertex array is copied into the current shared buffer.
7. The command encoder sets the pipeline, buffer, and uniforms.
8. One `drawPrimitives` call encodes the frame.
9. The command buffer presents the drawable.

[`GameView.swift`](../Sources/SpaceInvadersArcade/GameView.swift) — `draw(in:)`
owns the simulation loop.

[`Renderer.swift`](../Sources/SpaceInvadersArcade/Renderer.swift) — `render`
owns steps 4–9.

## 11. What Metal does *not* do here

- It does **not** move invaders. `Game.swift` owns the march.
- It does **not** decide collisions. `SpaceInvadersGame` resolves them.
- It does **not** spawn the mystery ship. The core does.
- It does **not** generate the sound.
- It does **not** store the high score.

That separation is deliberate. If the invaders stop moving, the bug is in the
core. If they move but are invisible, the bug is in the renderer. If they are
visible but the wrong colour, the bug is in the palette or the vertex layout.

## 12. Small experiments

Try these in a branch, then run `make check` and launch the app:

1. Change `unit` in `Renderer.swift` to 3 and see how the playfield no longer
   fills the design height. This is the world-to-screen mapping in action.
2. Change the fragment shader to return `float4(in.color.rgb, 0.5)` and watch
   the scene become translucent. This is per-pixel colour, applied after
   blending factors.
3. Remove the scanline loop and compare the image. The CRT look is entirely
   geometry.
4. Set `sampleCount = 1` in `GameView.swift` and inspect the edges of the
   pixel art. MSAA is most visible on curves and diagonals.

## 13. Where to go next

- Read [`Renderer.swift`](../Sources/SpaceInvadersArcade/Renderer.swift) from
  `render` downward, following the draw order.
- Read [`Canvas.swift`](../Sources/SpaceInvadersArcade/Canvas.swift) — `addTriangle`
  shows how each primitive becomes triangles.
- Read [`MetalShaders.swift`](../Sources/SpaceInvadersArcade/MetalShaders.swift) —
  `MetalShaderSource` is fewer than 40 lines; read it line by line.
- Read [`GameView.swift`](../Sources/SpaceInvadersArcade/GameView.swift) —
  `draw(in:)` is the fixed-step loop that keeps simulation deterministic.
- Then read the [Q&A](QnA/README.md) entries for the gameplay side.

The useful mental habit is to ask, for any visual: **what triangles is this made
of, and who appended them?**
