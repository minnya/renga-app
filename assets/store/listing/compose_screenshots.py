"""Composite raw device captures (from capture_screenshots.js) into final Play Store
listing screenshots: brand-gradient background + short marketing caption + rounded
device frame with soft shadow.

Input:  assets/store/listing/raw/<size>/<shot>.png   (git-ignored, one-off local output)
Output: assets/store/screenshots_en/<size>/<shot>.png

Usage: python compose_screenshots.py (requires Pillow, same as generate_screenshots.py)
"""

import os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = os.path.dirname(os.path.abspath(__file__))
RAW = os.path.join(ROOT, "raw")
OUT = os.path.join(ROOT, "..", "screenshots_en")

# Brand palette (design/system.md palette, docs/index.html hero gradient).
BG = (11, 13, 20)  # --bg
INFLUENCE_START = (255, 122, 69)  # --influence-start
INFLUENCE_END = (255, 182, 72)  # --influence-end
INTELLECT_START = (79, 107, 255)  # --intellect-start
INTELLECT_END = (126, 224, 255)  # --intellect-end
TEXT_WHITE = (243, 244, 248)

SIZES = {
    "phone": (1080, 1920),
    "tablet_7in": (1200, 1920),
    "tablet_10in": (1600, 2560),
}

CAPTIONS = {
    "01_feed": "See posts ranked by logic, not just followers",
    "02_discover_truth_vote": "Vote on what's actually true",
    "03_profile_scorecard": "Track your Influence and Intellect side by side",
    "04_daily_quiz": "Sharpen your mind with a daily logic quiz",
}

# Alternate accent per screenshot for visual variety while staying on-brand.
ACCENTS = {
    "01_feed": (INFLUENCE_START, INFLUENCE_END),
    "02_discover_truth_vote": (INTELLECT_START, INTELLECT_END),
    "03_profile_scorecard": (INFLUENCE_START, INFLUENCE_END),
    "04_daily_quiz": (INTELLECT_START, INTELLECT_END),
}


def font(size, bold=True):
    names = (
        ["arialbd.ttf", "Arial Bold.ttf", "DejaVuSans-Bold.ttf"]
        if bold
        else ["arial.ttf", "Arial.ttf", "DejaVuSans.ttf"]
    )
    for n in names:
        try:
            return ImageFont.truetype(n, size)
        except OSError:
            continue
    return ImageFont.load_default()


def make_background(w, h, accent_start, accent_end):
    """Dark base with a soft diagonal accent glow (top-left -> bottom-right)."""
    base = Image.new("RGB", (w, h), BG)

    glow = Image.new("RGB", (w, h), BG)
    gd = ImageDraw.Draw(glow)
    steps = 120
    for i in range(steps):
        t = i / (steps - 1)
        r = int(accent_start[0] * (1 - t) + accent_end[0] * t)
        g = int(accent_start[1] * (1 - t) + accent_end[1] * t)
        b = int(accent_start[2] * (1 - t) + accent_end[2] * t)
        x0 = int(-h + t * (w + h))
        gd.line([(x0, h), (x0 + h, 0)], fill=(r, g, b), width=int(h / steps) + 2)
    glow = glow.filter(ImageFilter.GaussianBlur(radius=w * 0.12))

    base = Image.blend(base, glow, alpha=0.32)

    # Subtle vignette: darken edges slightly.
    vignette = Image.new("L", (w, h), 0)
    vd = ImageDraw.Draw(vignette)
    vd.ellipse([-w * 0.3, -h * 0.2, w * 1.3, h * 1.1], fill=255)
    vignette = vignette.filter(ImageFilter.GaussianBlur(radius=w * 0.15))
    dark = Image.new("RGB", (w, h), (0, 0, 0))
    base = Image.composite(base, dark, vignette)

    return base


def rounded_mask(size, radius):
    mask = Image.new("L", size, 0)
    d = ImageDraw.Draw(mask)
    d.rounded_rectangle([(0, 0), (size[0] - 1, size[1] - 1)], radius=radius, fill=255)
    return mask


def paste_with_shadow(canvas, shot, box_xy, radius, shadow_alpha=110):
    """Paste `shot` onto canvas at box_xy with rounded corners + a soft drop shadow."""
    x, y = box_xy
    w, h = shot.size

    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    pad = int(w * 0.02)
    sd.rounded_rectangle(
        [x - pad, y - pad + int(h * 0.02), x + w + pad, y + h + pad + int(h * 0.02)],
        radius=radius + pad,
        fill=(0, 0, 0, shadow_alpha),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=w * 0.03))
    canvas.alpha_composite(shadow)

    mask = rounded_mask((w, h), radius)
    canvas.paste(shot.convert("RGBA"), (x, y), mask)

    border = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    bd = ImageDraw.Draw(border)
    bd.rounded_rectangle(
        [x, y, x + w - 1, y + h - 1], radius=radius, outline=(255, 255, 255, 40), width=2
    )
    canvas.alpha_composite(border)


def wrap_text(draw, text, fnt, max_width):
    words = text.split()
    lines = []
    cur = ""
    for word in words:
        trial = (cur + " " + word).strip()
        if draw.textlength(trial, font=fnt) <= max_width:
            cur = trial
        else:
            if cur:
                lines.append(cur)
            cur = word
    if cur:
        lines.append(cur)
    return lines


def compose_one(canvas_w, canvas_h, shot_key, raw_path, out_path):
    accent_start, accent_end = ACCENTS[shot_key]
    canvas = make_background(canvas_w, canvas_h, accent_start, accent_end).convert("RGBA")
    draw = ImageDraw.Draw(canvas)

    caption = CAPTIONS[shot_key]
    cap_font_size = int(canvas_w * 0.062)
    cap_font = font(cap_font_size, bold=True)
    side_margin = int(canvas_w * 0.09)
    max_text_width = canvas_w - side_margin * 2
    lines = wrap_text(draw, caption, cap_font, max_text_width)
    line_height = int(cap_font_size * 1.22)
    text_block_h = line_height * len(lines)
    top_area_h = int(canvas_h * 0.145)
    text_top = max(int(canvas_h * 0.045), top_area_h - text_block_h)
    for i, line in enumerate(lines):
        tw = draw.textlength(line, font=cap_font)
        tx = (canvas_w - tw) / 2
        ty = text_top + i * line_height
        draw.text((tx + 2, ty + 2), line, font=cap_font, fill=(0, 0, 0, 120))
        draw.text((tx, ty), line, font=cap_font, fill=TEXT_WHITE)

    shot = Image.open(raw_path).convert("RGB")
    shot_area_top = int(canvas_h * 0.145) + text_block_h + int(canvas_h * 0.02)
    bottom_margin = int(canvas_h * 0.035)
    side_pad = int(canvas_w * 0.06)
    avail_w = canvas_w - side_pad * 2
    avail_h = canvas_h - shot_area_top - bottom_margin

    scale = min(avail_w / shot.width, avail_h / shot.height)
    new_w = int(shot.width * scale)
    new_h = int(shot.height * scale)
    shot_resized = shot.resize((new_w, new_h), Image.LANCZOS)

    x = (canvas_w - new_w) // 2
    y = shot_area_top + (avail_h - new_h) // 2
    radius = int(canvas_w * 0.045)

    paste_with_shadow(canvas, shot_resized, (x, y), radius)

    canvas.convert("RGB").save(out_path, "PNG")


def main():
    for size_name, (w, h) in SIZES.items():
        out_dir = os.path.join(OUT, size_name)
        os.makedirs(out_dir, exist_ok=True)
        for shot_key in CAPTIONS:
            raw_path = os.path.join(RAW, size_name, f"{shot_key}.png")
            out_path = os.path.join(out_dir, f"{shot_key}.png")
            compose_one(w, h, shot_key, raw_path, out_path)
            print("wrote", out_path)


if __name__ == "__main__":
    main()
