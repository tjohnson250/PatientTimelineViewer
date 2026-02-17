#!/usr/bin/env python3
"""Generate 3-layer visionOS app icon for Patient Timeline 3D.

Creates a "Timeline Clock" icon with:
  - Back layer: dark navy circle with radial gradient
  - Middle layer: colored arc ring with clock markers
  - Front layer: medical cross, ECG waveform, event dots

All drawing is done at 4x supersampling (4096x4096) then downscaled
to 1024x1024 with Lanczos resampling for smooth antialiasing.
"""

import json
import math
import os
from PIL import Image, ImageDraw, ImageFilter

# --- Constants ---
FINAL_SIZE = 1024
SUPERSAMPLE = 4
SIZE = FINAL_SIZE * SUPERSAMPLE  # 4096
CENTER = SIZE // 2
PI2 = 2 * math.pi

# Asset catalog base path (relative to this script)
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.join(SCRIPT_DIR, "..")
ICON_BASE = os.path.join(
    PROJECT_DIR,
    "PatientTimeline3D",
    "Assets.xcassets",
    "AppIcon.solidimagestack",
)

# Colors matching ColorScheme.swift
COLORS = {
    "encounter": (52, 152, 219),    # #3498db Blue
    "diagnosis": (231, 76, 60),     # #e74c3c Coral
    "lab": (39, 174, 96),           # #27ae60 Green
    "procedure": (155, 89, 182),    # #9b59b6 Purple
    "prescribing": (230, 126, 34),  # #e67e22 Orange
    "vital": (26, 188, 156),        # #1abc9c Teal
}

NAVY = (26, 26, 46)         # #1a1a2e
NAVY_LIGHT = (40, 40, 70)   # Slightly lighter center for gradient


def create_contents_json(filename: str) -> dict:
    """Create a Contents.json for an imageset."""
    return {
        "images": [
            {
                "filename": filename,
                "idiom": "vision",
                "scale": "2x",
            }
        ],
        "info": {
            "author": "xcode",
            "version": 1,
        },
    }


def save_layer(img: Image.Image, layer_name: str, png_name: str):
    """Downscale and save a layer to the correct asset catalog location."""
    final = img.resize((FINAL_SIZE, FINAL_SIZE), Image.LANCZOS)

    imageset_dir = os.path.join(
        ICON_BASE, f"{layer_name}.solidimagestacklayer", "Content.imageset"
    )
    os.makedirs(imageset_dir, exist_ok=True)

    # Save PNG
    final.save(os.path.join(imageset_dir, png_name), "PNG")

    # Write Contents.json
    contents = create_contents_json(png_name)
    with open(os.path.join(imageset_dir, "Contents.json"), "w") as f:
        json.dump(contents, f, indent=2)
        f.write("\n")

    print(f"  Saved {layer_name}/Content.imageset/{png_name} ({FINAL_SIZE}x{FINAL_SIZE})")


# =============================================================================
# Back Layer: Navy circle with radial gradient
# =============================================================================
def generate_back_layer() -> Image.Image:
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Build radial gradient within circle
    radius = SIZE // 2 - 40  # small margin
    for r in range(radius, 0, -1):
        t = r / radius  # 1 at edge, 0 at center
        color = tuple(
            int(NAVY_LIGHT[c] + (NAVY[c] - NAVY_LIGHT[c]) * t) for c in range(3)
        )
        bbox = (CENTER - r, CENTER - r, CENTER + r, CENTER + r)
        draw.ellipse(bbox, fill=color + (255,))

    return img


# =============================================================================
# Middle Layer: Clock ring with colored arcs and marker dots
# =============================================================================
def generate_middle_layer() -> Image.Image:
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))

    # Ring parameters (in supersampled coords)
    inner_r = int(310 * SUPERSAMPLE)
    outer_r = int(400 * SUPERSAMPLE)
    mid_r = (inner_r + outer_r) // 2

    # Create ring mask
    ring_mask = Image.new("L", (SIZE, SIZE), 0)
    ring_draw = ImageDraw.Draw(ring_mask)
    ring_draw.ellipse(
        (CENTER - outer_r, CENTER - outer_r, CENTER + outer_r, CENTER + outer_r),
        fill=255,
    )
    ring_draw.ellipse(
        (CENTER - inner_r, CENTER - inner_r, CENTER + inner_r, CENTER + inner_r),
        fill=0,
    )

    # Draw colored arc segments
    arc_colors = list(COLORS.values())
    arc_names = list(COLORS.keys())
    n_arcs = len(arc_colors)
    gap_deg = 5  # degrees gap between arcs
    total_gap = gap_deg * n_arcs
    arc_span = (360 - total_gap) / n_arcs  # degrees per arc

    arc_canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    arc_draw = ImageDraw.Draw(arc_canvas)

    start_angle = -90  # 12 o'clock position
    for i in range(n_arcs):
        a_start = start_angle + i * (arc_span + gap_deg)
        a_end = a_start + arc_span
        color = arc_colors[i]

        # Draw filled pieslice on temporary canvas, then mask to ring
        temp = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
        temp_draw = ImageDraw.Draw(temp)
        bbox = (CENTER - outer_r - 10, CENTER - outer_r - 10,
                CENTER + outer_r + 10, CENTER + outer_r + 10)
        temp_draw.pieslice(bbox, a_start, a_end, fill=color + (220,))

        # Mask to ring shape
        temp.putalpha(Image.fromarray(
            __import__("numpy").minimum(
                __import__("numpy").array(temp.split()[3]),
                __import__("numpy").array(ring_mask),
            )
        ))
        arc_canvas = Image.alpha_composite(arc_canvas, temp)

    img = Image.alpha_composite(img, arc_canvas)

    # Draw thin ring outline strokes for definition
    outline_draw = ImageDraw.Draw(img)
    stroke_w = max(2, SUPERSAMPLE)
    # Outer ring outline
    outline_draw.ellipse(
        (CENTER - outer_r, CENTER - outer_r, CENTER + outer_r, CENTER + outer_r),
        outline=(200, 200, 220, 100),
        width=stroke_w,
    )
    # Inner ring outline
    outline_draw.ellipse(
        (CENTER - inner_r, CENTER - inner_r, CENTER + inner_r, CENTER + inner_r),
        outline=(200, 200, 220, 100),
        width=stroke_w,
    )

    # 12 clock-position marker dots at ring midpoint
    dot_r = int(8 * SUPERSAMPLE)
    for i in range(12):
        angle = PI2 * i / 12 - math.pi / 2  # start at 12 o'clock
        dx = int(mid_r * math.cos(angle))
        dy = int(mid_r * math.sin(angle))
        cx, cy = CENTER + dx, CENTER + dy
        outline_draw.ellipse(
            (cx - dot_r, cy - dot_r, cx + dot_r, cy + dot_r),
            fill=(180, 180, 200, 160),
        )

    return img


# =============================================================================
# Front Layer: Medical cross, ECG waveform, event dots
# =============================================================================
def generate_front_layer() -> Image.Image:
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # --- White medical cross at center ---
    cross_w = int(55 * SUPERSAMPLE)   # width of each bar
    cross_h = int(160 * SUPERSAMPLE)  # height of each bar
    corner_r = int(14 * SUPERSAMPLE)  # corner radius

    # Vertical bar
    draw.rounded_rectangle(
        (CENTER - cross_w // 2, CENTER - cross_h // 2,
         CENTER + cross_w // 2, CENTER + cross_h // 2),
        radius=corner_r,
        fill=(255, 255, 255, 240),
    )
    # Horizontal bar
    draw.rounded_rectangle(
        (CENTER - cross_h // 2, CENTER - cross_w // 2,
         CENTER + cross_h // 2, CENTER + cross_w // 2),
        radius=corner_r,
        fill=(255, 255, 255, 240),
    )

    # --- Stylized ECG waveform line below cross ---
    ecg_y_base = CENTER + int(120 * SUPERSAMPLE)  # below the cross
    ecg_x_start = CENTER - int(140 * SUPERSAMPLE)
    ecg_x_end = CENTER + int(140 * SUPERSAMPLE)
    ecg_width = ecg_x_end - ecg_x_start

    # Build ECG points: flat - small dip - big spike - valley - return - flat
    points = []
    segments = [
        (0.00, 0.0),
        (0.20, 0.0),
        (0.28, 0.02),   # small P wave
        (0.33, 0.0),
        (0.38, -0.03),  # small Q dip
        (0.42, -0.25),  # R spike (up = negative y)
        (0.46, 0.12),   # S valley
        (0.50, 0.0),
        (0.55, -0.04),  # T wave
        (0.62, 0.0),
        (1.00, 0.0),
    ]
    amp = int(100 * SUPERSAMPLE)
    stroke_w = int(5 * SUPERSAMPLE)

    for frac, val in segments:
        x = ecg_x_start + int(frac * ecg_width)
        y = ecg_y_base + int(val * amp)
        points.append((x, y))

    # Draw ECG with white-ish green tint
    if len(points) >= 2:
        draw.line(points, fill=(200, 255, 220, 200), width=stroke_w, joint="curve")

    # --- 6 colored event dots around center at radius ~220px ---
    dot_radius = int(220 * SUPERSAMPLE)
    dot_size = int(18 * SUPERSAMPLE)
    dot_colors = list(COLORS.values())
    n_dots = len(dot_colors)

    for i in range(n_dots):
        angle = PI2 * i / n_dots - math.pi / 2
        dx = int(dot_radius * math.cos(angle))
        dy = int(dot_radius * math.sin(angle))
        cx, cy = CENTER + dx, CENTER + dy

        # Colored dot with slight glow effect: draw larger semi-transparent first
        glow_size = dot_size + int(6 * SUPERSAMPLE)
        draw.ellipse(
            (cx - glow_size, cy - glow_size, cx + glow_size, cy + glow_size),
            fill=dot_colors[i] + (60,),
        )
        draw.ellipse(
            (cx - dot_size, cy - dot_size, cx + dot_size, cy + dot_size),
            fill=dot_colors[i] + (230,),
        )

    return img


# =============================================================================
# Main
# =============================================================================
def main():
    print("Generating Patient Timeline 3D app icon layers...")
    print(f"  Supersample: {SIZE}x{SIZE} -> {FINAL_SIZE}x{FINAL_SIZE}")
    print(f"  Output: {ICON_BASE}")
    print()

    # Import numpy check (used for alpha compositing in middle layer)
    try:
        import numpy  # noqa: F401
    except ImportError:
        print("ERROR: numpy is required. Install with: pip3 install numpy")
        return

    print("Generating Back layer (navy gradient circle)...")
    back = generate_back_layer()
    save_layer(back, "Back", "icon_back.png")

    print("Generating Middle layer (clock ring with arcs)...")
    middle = generate_middle_layer()
    save_layer(middle, "Middle", "icon_middle.png")

    print("Generating Front layer (cross, ECG, dots)...")
    front = generate_front_layer()
    save_layer(front, "Front", "icon_front.png")

    print()
    print("Done! Open Xcode to verify the icon in the asset catalog.")


if __name__ == "__main__":
    main()
