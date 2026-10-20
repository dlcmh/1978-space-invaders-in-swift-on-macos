#!/usr/bin/env python3
"""Generate the SPACE INVADERS app icon from original procedural pixel art."""
from __future__ import annotations

import os
import subprocess
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
RESOURCES = ROOT / "Resources"
ICONSET = RESOURCES / "AppIcon.iconset"
ICON = RESOURCES / "AppIcon.png"
ICNS = RESOURCES / "AppIcon.icns"

S = 2048
OUT = 1024
MARGIN = 112
CORNER = 420

CRAB = [
    "..#.....#..",
    "...#...#...",
    "..#######..",
    ".##.###.##.",
    "###########",
    "#.#######.#",
    "#.#.....#.#",
    "...##.##...",
]

CANNON = [
    "......#......",
    ".....###.....",
    ".....###.....",
    ".###########.",
    "#############",
    "#############",
    "#############",
    "#############",
]

BUNKER = [
    "..##################..",
    ".####################.",
    "######################",
    "######################",
    "######################",
    "######################",
    "#########....#########",
    "#######........#######",
    "#####............#####",
]


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def rounded_mask(size: int, margin: int, radius: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle(
        (margin, margin, size - margin, size - margin), radius=radius, fill=255
    )
    return mask


def draw_pixels(draw: ImageDraw.ImageDraw, rows, x, y, pixel, fill):
    for row_index, row in enumerate(rows):
        for column_index, character in enumerate(row):
            if character != "#":
                continue
            left = x + column_index * pixel
            top = y + row_index * pixel
            draw.rectangle((left, top, left + pixel - 1, top + pixel - 1), fill=fill)


def glow_layer(size: int, painter, blur: int) -> Image.Image:
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    painter(ImageDraw.Draw(layer))
    return layer.filter(ImageFilter.GaussianBlur(blur))


def main():
    RESOURCES.mkdir(exist_ok=True)
    image = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    mask = rounded_mask(S, MARGIN, CORNER)

    background = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    bg_draw = ImageDraw.Draw(background)
    for y in range(MARGIN, S - MARGIN):
        t = (y - MARGIN) / max(1, S - 2 * MARGIN)
        bg_draw.line((0, y, S, y), fill=lerp((3, 6, 18), (10, 20, 48), t) + (255,))
    image.paste(background, (0, 0), mask)
    draw = ImageDraw.Draw(image)

    # Ambient cyan and magenta light.
    aura = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    aura_draw = ImageDraw.Draw(aura)
    aura_draw.ellipse((130, 380, 1900, 1680), fill=(22, 92, 230, 58))
    aura_draw.ellipse((900, 120, 2080, 1050), fill=(212, 40, 140, 34))
    aura = aura.filter(ImageFilter.GaussianBlur(230))
    image.alpha_composite(
        Image.composite(aura, Image.new("RGBA", (S, S), (0, 0, 0, 0)), mask)
    )
    draw = ImageDraw.Draw(image)

    # Deterministic star field.
    star_rng = 1978
    for index in range(76):
        star_rng = (star_rng * 1103515245 + 12345) & 0x7FFFFFFF
        x = MARGIN + 40 + star_rng % (S - 2 * MARGIN - 80)
        star_rng = (star_rng * 1103515245 + 12345) & 0x7FFFFFFF
        y = MARGIN + 40 + star_rng % (S - 2 * MARGIN - 80)
        radius = 3 + (star_rng >> 8) % 7
        alpha = 70 + (star_rng >> 4) % 140
        star = (200, 224, 255, alpha)
        draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill=star)

    # A subtle circuit grid.
    grid = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    grid_draw = ImageDraw.Draw(grid)
    for offset in range(320, S - 240, 112):
        grid_draw.line((320, offset, S - 320, offset), fill=(52, 108, 210, 18), width=2)
        grid_draw.line((offset, 320, offset, S - 320), fill=(52, 108, 210, 18), width=2)
    image.alpha_composite(grid)

    # The invader, with a magenta/cyan double exposure for depth.
    crab_pixel = 88
    crab_width = len(CRAB[0]) * crab_pixel
    crab_x = (S - crab_width) // 2
    crab_y = 470

    crab_glow = glow_layer(
        S,
        lambda d: draw_pixels(
            d, CRAB, crab_x - 8, crab_y - 8, crab_pixel + 16, (56, 220, 255, 170)
        ),
        58,
    )
    image.alpha_composite(crab_glow)
    draw = ImageDraw.Draw(image)
    draw_pixels(draw, CRAB, crab_x + 12, crab_y + 18, crab_pixel, (238, 44, 122, 220))
    draw_pixels(draw, CRAB, crab_x, crab_y, crab_pixel, (70, 232, 255, 255))

    # Highlight cells on the upper body.
    for row_index, row in enumerate(CRAB[:3]):
        for column_index, character in enumerate(row):
            if character != "#":
                continue
            left = crab_x + column_index * crab_pixel + 14
            top = crab_y + row_index * crab_pixel + 14
            draw.rectangle(
                (left, top, left + crab_pixel - 32, top + crab_pixel - 36),
                fill=(210, 252, 255, 110),
            )

    # Cannon and laser.
    cannon_pixel = 58
    cannon_width = len(CANNON[0]) * cannon_pixel
    cannon_x = (S - cannon_width) // 2
    cannon_y = 1390
    laser_x = S // 2
    laser_top = crab_y + len(CRAB) * crab_pixel + 28
    laser_bottom = cannon_y - 24
    laser_glow = glow_layer(
        S,
        lambda d: d.rectangle(
            (laser_x - 26, laser_top, laser_x + 26, laser_bottom), fill=(120, 255, 170, 190)
        ),
        45,
    )
    image.alpha_composite(laser_glow)
    draw = ImageDraw.Draw(image)
    draw.rectangle((laser_x - 6, laser_top, laser_x + 6, laser_bottom), fill=(232, 255, 240, 255))
    draw.rectangle((laser_x - 2, laser_top, laser_x + 2, laser_bottom), fill=(255, 255, 255, 255))

    cannon_glow = glow_layer(
        S,
        lambda d: draw_pixels(
            d, CANNON, cannon_x - 8, cannon_y - 8, cannon_pixel + 16, (80, 255, 140, 175)
        ),
        55,
    )
    image.alpha_composite(cannon_glow)
    draw = ImageDraw.Draw(image)
    draw_pixels(draw, CANNON, cannon_x, cannon_y, cannon_pixel, (110, 255, 150, 255))

    # Two incoming bombs.
    for x, y in ((570, 1080), (1460, 1150)):
        bomb_glow = glow_layer(
            S,
            lambda d, x=x, y=y: d.rectangle((x - 24, y, x + 24, y + 170), fill=(255, 150, 40, 160)),
            32,
        )
        image.alpha_composite(bomb_glow)
        draw = ImageDraw.Draw(image)
        for segment in range(5):
            offset = -12 if segment % 2 == 0 else 12
            draw.rectangle(
                (x + offset - 8, y + segment * 34, x + offset + 8, y + segment * 34 + 26),
                fill=(255, 176, 70, 255),
            )

    # Bunkers at the lower edge.
    bunker_pixel = 25
    for bunker_x in (330, 1230):
        draw_pixels(
            draw,
            BUNKER,
            bunker_x,
            1710,
            bunker_pixel,
            (64, 230, 112, 230),
        )

    # A few drifting shield chips.
    for x, y, size in ((300, 1600, 12), (320, 1640, 7), (1740, 1590, 10), (1710, 1634, 6)):
        draw.rectangle((x, y, x + size, y + size), fill=(64, 230, 112, 160))

    # Fine scanlines and a soft vignette.
    scan = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    scan_draw = ImageDraw.Draw(scan)
    for y in range(0, S, 8):
        scan_draw.line((0, y, S, y), fill=(0, 0, 0, 28))
    scan = Image.composite(scan, Image.new("RGBA", (S, S), (0, 0, 0, 0)), mask)
    image.alpha_composite(scan)

    vignette = Image.new("L", (S, S), 0)
    vignette_draw = ImageDraw.Draw(vignette)
    vignette_draw.ellipse((-S * 0.12, -S * 0.12, S * 1.12, S * 1.12), fill=255)
    vignette = vignette.filter(ImageFilter.GaussianBlur(220))
    dark = Image.new("RGBA", (S, S), (0, 0, 0, 92))
    dark.putalpha(Image.eval(vignette, lambda value: 255 - value))
    image.alpha_composite(
        Image.composite(dark, Image.new("RGBA", (S, S), (0, 0, 0, 0)), mask)
    )

    final_alpha = image.getchannel("A")
    final_alpha = Image.composite(final_alpha, Image.new("L", (S, S), 0), mask)
    image.putalpha(final_alpha)

    image = image.resize((OUT, OUT), Image.Resampling.LANCZOS)
    image.save(ICON)

    ICONSET.mkdir(exist_ok=True)
    sizes = [16, 32, 128, 256, 512]
    for size in sizes:
        image.resize((size, size), Image.Resampling.LANCZOS).save(
            ICONSET / f"icon_{size}x{size}.png"
        )
        image.resize((size * 2, size * 2), Image.Resampling.LANCZOS).save(
            ICONSET / f"icon_{size}x{size}@2x.png"
        )

    subprocess.run(["iconutil", "-c", "icns", str(ICONSET), "-o", str(ICNS)], check=True)
    print(f"Wrote {ICON.relative_to(ROOT)} and {ICNS.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
