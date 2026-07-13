"""Generate PLACEHOLDER MOCKUP Play Store screenshots for Renga (English).

These are wireframe-style mockups, not real app captures. They exist so the
Play Console listing has valid image dimensions to work with until real
device screenshots are captured post-implementation. Swap out for actual
captures before submitting the store listing for review.
"""

import os
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.abspath(__file__))
OUT_PHONE = os.path.join(ROOT, "..", "screenshots_en", "phone")
OUT_TABLET7 = os.path.join(ROOT, "..", "screenshots_en", "tablet_7in")
OUT_TABLET10 = os.path.join(ROOT, "..", "screenshots_en", "tablet_10in")
for d in (OUT_PHONE, OUT_TABLET7, OUT_TABLET10):
    os.makedirs(d, exist_ok=True)

# Renga brand palette (from design/system.md palette + design/product.md 5章)
BG_DARK = (17, 18, 27)
CARD = (30, 32, 44)
CARD_LINE = (54, 57, 74)
TEXT_WHITE = (245, 245, 248)
TEXT_MUTED = (150, 153, 168)
ACCENT_BLUE = (90, 130, 255)
INFLUENCE_WARM = (255, 140, 66)
INTELLECT_COOL = (110, 100, 240)
TRUTH_GREEN = (61, 191, 122)
TRUTH_RED = (232, 84, 84)
AVATAR_COLORS = [
    (255, 140, 66), (224, 108, 96), (176, 96, 140),
    (150, 96, 214), (110, 100, 240),
]


def font(size, bold=True):
    names = (
        ["arialbd.ttf", "Arial Bold.ttf"] if bold else ["arial.ttf", "Arial.ttf"]
    )
    for n in names:
        try:
            return ImageFont.truetype(n, size)
        except OSError:
            continue
    return ImageFont.load_default()


def rounded(draw, box, radius, fill=None, outline=None, width=1):
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


def gradient_bg(w, h, c1, c2):
    base = Image.new("RGB", (w, h), c1)
    top = Image.new("RGB", (w, h), c2)
    mask = Image.new("L", (w, h))
    mask_data = []
    for y in range(h):
        mask_data.extend([int(255 * (y / h))] * w)
    mask.putdata(mask_data)
    base.paste(top, (0, 0), mask)
    return base


def status_bar(draw, w, pad, s):
    draw.text((pad, int(14 * s)), "Renga", font=int(30 * s) and font(int(30 * s)), fill=TEXT_WHITE)


def watermark(img, draw, w, h, s, caption):
    bar_h = int(110 * s)
    y0 = h // 2 - bar_h // 2
    draw.rectangle([0, y0, w, y0 + bar_h], fill=(0, 0, 0))
    f1 = font(int(30 * s))
    f2 = font(int(20 * s), bold=False)
    t1 = "PLACEHOLDER MOCKUP"
    t2 = caption
    bbox1 = draw.textbbox((0, 0), t1, font=f1)
    bbox2 = draw.textbbox((0, 0), t2, font=f2)
    draw.text(((w - (bbox1[2] - bbox1[0])) / 2, y0 + int(18 * s)), t1, font=f1, fill=(255, 255, 255))
    draw.text(((w - (bbox2[2] - bbox2[0])) / 2, y0 + int(60 * s)), t2, font=f2, fill=(210, 210, 210))


def bar_placeholder(draw, x, y, w, h, color):
    rounded(draw, [x, y, x + w, y + h], radius=h // 2, fill=color)


def icon_heart(draw, cx, cy, r, color, width):
    lobe = r * 0.62
    draw.ellipse([cx - r, cy - r * 0.35 - lobe * 0.5, cx - r + lobe * 2, cy - r * 0.35 + lobe * 0.5], outline=color, width=width)
    draw.ellipse([cx + r - lobe * 2, cy - r * 0.35 - lobe * 0.5, cx + r, cy - r * 0.35 + lobe * 0.5], outline=color, width=width)
    draw.polygon(
        [(cx - r * 0.95, cy - r * 0.15), (cx + r * 0.95, cy - r * 0.15), (cx, cy + r)],
        outline=color,
    )


def icon_comment(draw, cx, cy, r, color, width):
    box = [cx - r, cy - r * 0.8, cx + r, cy + r * 0.5]
    rounded(draw, box, radius=int(r * 0.3), outline=color, width=width)
    draw.polygon([(cx - r * 0.3, cy + r * 0.5), (cx + r * 0.1, cy + r * 0.5), (cx - r * 0.15, cy + r * 1.0)], fill=color)


def icon_repost(draw, cx, cy, r, color, width):
    draw.arc([cx - r, cy - r, cx + r * 0.3, cy + r * 0.3], start=200, end=90, fill=color, width=width)
    draw.arc([cx - r * 0.3, cy - r * 0.3, cx + r, cy + r], start=20, end=270, fill=color, width=width)
    draw.polygon([(cx + r * 0.3, cy - r), (cx + r * 0.7, cy - r * 0.55), (cx + r * 0.1, cy - r * 0.55)], fill=color)
    draw.polygon([(cx - r * 0.3, cy + r), (cx - r * 0.7, cy + r * 0.55), (cx - r * 0.1, cy + r * 0.55)], fill=color)


def icon_gavel(draw, cx, cy, r, color, width):
    draw.line([cx - r * 0.6, cy - r * 0.6, cx + r * 0.1, cy + r * 0.1], fill=color, width=int(width * 2.2))
    draw.line([cx - r * 0.2, cy - r * 0.9, cx + r * 0.5, cy - r * 0.2], fill=color, width=int(width * 2.2))
    draw.line([cx - r * 0.7, cy + r * 0.3, cx + r * 0.7, cy + r * 0.9], fill=color, width=width)


def icon_share(draw, cx, cy, r, color, width):
    draw.line([cx, cy + r, cx, cy - r * 0.2], fill=color, width=width)
    draw.line([cx, cy - r, cx - r * 0.5, cy - r * 0.4], fill=color, width=width)
    draw.line([cx, cy - r, cx + r * 0.5, cy - r * 0.4], fill=color, width=width)


ACTION_ICONS = [icon_heart, icon_comment, icon_repost, icon_gavel, icon_share]


def draw_action_bar(draw, x, y, r, gap, color, width):
    ix = x
    for fn in ACTION_ICONS:
        fn(draw, ix + r, y + r, r, color, width)
        ix += gap


def screen_feed(w, h, s):
    img = gradient_bg(w, h, BG_DARK, (20, 21, 32))
    draw = ImageDraw.Draw(img)
    pad = int(48 * s)
    draw.text((pad, int(56 * s)), "Renga", font=font(int(56 * s)), fill=TEXT_WHITE)
    draw.line([pad, int(150 * s), w - pad, int(150 * s)], fill=INFLUENCE_WARM, width=int(5 * s))

    # layer filter chips
    chip_y = int(180 * s)
    chips = ["Everyone", "Top 25%", "Top 5%"]
    cx = pad
    for i, c in enumerate(chips):
        cf = font(int(24 * s))
        tb = draw.textbbox((0, 0), c, font=cf)
        cw = (tb[2] - tb[0]) + int(48 * s)
        ch = int(56 * s)
        fill = ACCENT_BLUE if i == 1 else CARD
        rounded(draw, [cx, chip_y, cx + cw, chip_y + ch], radius=ch // 2, fill=fill, outline=CARD_LINE, width=1)
        draw.text((cx + int(24 * s), chip_y + int(14 * s)), c, font=cf, fill=TEXT_WHITE)
        cx += cw + int(16 * s)

    y = chip_y + int(90 * s)
    card_h = int(260 * s)
    gap = int(28 * s)
    n_cards = max(2, (h - y - int(60 * s)) // (card_h + gap))
    for i in range(n_cards):
        cy = y + i * (card_h + gap)
        rounded(draw, [pad, cy, w - pad, cy + card_h], radius=int(24 * s), fill=CARD, outline=CARD_LINE, width=1)
        av_d = int(72 * s)
        av_x, av_y = pad + int(28 * s), cy + int(28 * s)
        draw.ellipse([av_x, av_y, av_x + av_d, av_y + av_d], fill=AVATAR_COLORS[i % len(AVATAR_COLORS)])
        name_x = av_x + av_d + int(20 * s)
        bar_placeholder(draw, name_x, av_y + int(6 * s), int(260 * s), int(22 * s), CARD_LINE)
        if i % 2 == 0:
            badge_w = int(80 * s)
            rounded(draw, [name_x + int(280 * s), av_y + int(4 * s), name_x + int(280 * s) + badge_w, av_y + int(4 * s) + int(26 * s)], radius=int(13 * s), fill=INTELLECT_COOL)
            draw.text((name_x + int(292 * s), av_y + int(7 * s)), "Top 5%", font=font(int(16 * s)), fill=(255, 255, 255))
        bar_placeholder(draw, name_x, av_y + int(38 * s), int(160 * s), int(18 * s), CARD_LINE)

        body_y = av_y + av_d + int(20 * s)
        bar_placeholder(draw, pad + int(28 * s), body_y, w - pad * 2 - int(56 * s), int(20 * s), CARD_LINE)
        bar_placeholder(draw, pad + int(28 * s), body_y + int(32 * s), int((w - pad * 2 - int(56 * s)) * 0.7), int(20 * s), CARD_LINE)

        icon_y = cy + card_h - int(56 * s)
        draw_action_bar(draw, pad + int(28 * s), icon_y, int(15 * s), int(64 * s), TEXT_MUTED, max(1, int(2.4 * s)))

    watermark(img, draw, w, h, s, "Feed — layer filter & intellect badges")
    return img


def screen_discover(w, h, s):
    img = gradient_bg(w, h, BG_DARK, (22, 18, 34))
    draw = ImageDraw.Draw(img)
    pad = int(48 * s)
    draw.text((pad, int(56 * s)), "Discover", font=font(int(56 * s)), fill=TEXT_WHITE)
    draw.line([pad, int(150 * s), w - pad, int(150 * s)], fill=INTELLECT_COOL, width=int(5 * s))

    card_y = int(200 * s)
    card_h = int(440 * s)
    rounded(draw, [pad, card_y, w - pad, card_y + card_h], radius=int(24 * s), fill=CARD, outline=CARD_LINE, width=1)

    av_d = int(72 * s)
    av_x, av_y = pad + int(28 * s), card_y + int(28 * s)
    draw.ellipse([av_x, av_y, av_x + av_d, av_y + av_d], fill=AVATAR_COLORS[3])
    name_x = av_x + av_d + int(20 * s)
    bar_placeholder(draw, name_x, av_y + int(6 * s), int(220 * s), int(22 * s), CARD_LINE)
    bar_placeholder(draw, name_x, av_y + int(38 * s), int(140 * s), int(18 * s), CARD_LINE)

    body_y = av_y + av_d + int(24 * s)
    bar_placeholder(draw, pad + int(28 * s), body_y, w - pad * 2 - int(56 * s), int(20 * s), CARD_LINE)
    bar_placeholder(draw, pad + int(28 * s), body_y + int(32 * s), int((w - pad * 2 - int(56 * s)) * 0.8), int(20 * s), CARD_LINE)

    # intelligence meter
    meter_y = body_y + int(90 * s)
    meter_x0, meter_x1 = pad + int(28 * s), w - pad - int(28 * s)
    meter_h = int(46 * s)
    split = meter_x0 + int((meter_x1 - meter_x0) * 0.5)
    rounded(draw, [meter_x0, meter_y, split, meter_y + meter_h], radius=int(23 * s), fill=TRUTH_GREEN)
    draw.rectangle([split - int(23 * s), meter_y, meter_x1, meter_y + meter_h], fill=TRUTH_RED)
    draw.ellipse([meter_x1 - meter_h, meter_y, meter_x1, meter_y + meter_h], fill=TRUTH_RED)
    lf = font(int(20 * s))
    draw.text((meter_x0 + int(20 * s), meter_y + int(11 * s)), "TRUE 50% (50)", font=lf, fill=(15, 40, 25))
    tb = draw.textbbox((0, 0), "FALSE 50% (50)", font=lf)
    draw.text((meter_x1 - int(20 * s) - (tb[2] - tb[0]), meter_y + int(11 * s)), "FALSE 50% (50)", font=lf, fill=(60, 10, 10))

    cap_y = meter_y + meter_h + int(20 * s)
    draw.text((pad + int(28 * s), cap_y), "Truth Vote result — verified by Top 25% users", font=font(int(20 * s), bold=False), fill=TEXT_MUTED)

    icon_y = card_y + card_h - int(56 * s)
    draw_action_bar(draw, pad + int(28 * s), icon_y, int(15 * s), int(64 * s), TEXT_MUTED, max(1, int(2.4 * s)))

    # second, pending card
    card2_y = card_y + card_h + int(28 * s)
    card2_h = int(180 * s)
    if card2_y + card2_h < h - int(60 * s):
        rounded(draw, [pad, card2_y, w - pad, card2_y + card2_h], radius=int(24 * s), fill=CARD, outline=CARD_LINE, width=1)
        dot_r = int(9 * s)
        dot_y = card2_y + int(24 * s) + int(13 * s)
        draw.ellipse([pad + int(28 * s), dot_y - dot_r, pad + int(28 * s) + dot_r * 2, dot_y + dot_r], outline=INFLUENCE_WARM, width=max(1, int(3 * s)))
        draw.text((pad + int(28 * s) + dot_r * 2 + int(14 * s), card2_y + int(24 * s)), "Deliberation in progress — 45 voters", font=font(int(22 * s)), fill=TEXT_WHITE)
        draw.text((pad + int(28 * s), card2_y + int(64 * s)), "Closes in 12h 30m", font=font(int(20 * s), bold=False), fill=TEXT_MUTED)

    watermark(img, draw, w, h, s, "Discover — Truth Vote intelligence meter")
    return img


def screen_profile(w, h, s):
    img = gradient_bg(w, h, BG_DARK, (24, 20, 30))
    draw = ImageDraw.Draw(img)
    pad = int(48 * s)
    draw.text((pad, int(56 * s)), "Profile", font=font(int(56 * s)), fill=TEXT_WHITE)
    draw.line([pad, int(150 * s), w - pad, int(150 * s)], fill=ACCENT_BLUE, width=int(5 * s))

    av_d = int(140 * s)
    av_x = w // 2 - av_d // 2
    av_y = int(190 * s)
    draw.ellipse([av_x, av_y, av_x + av_d, av_y + av_d], fill=AVATAR_COLORS[4])
    name_w = int(240 * s)
    bar_placeholder(draw, w // 2 - name_w // 2, av_y + av_d + int(24 * s), name_w, int(26 * s), CARD_LINE)

    badge_w, badge_h = int(140 * s), int(40 * s)
    bx = w // 2 - badge_w // 2
    by = av_y + av_d + int(64 * s)
    rounded(draw, [bx, by, bx + badge_w, by + badge_h], radius=badge_h // 2, fill=INTELLECT_COOL)
    draw.text((bx + int(20 * s), by + int(9 * s)), "Top 5% Intellect", font=font(int(18 * s)), fill=(255, 255, 255))

    stats_y = by + badge_h + int(50 * s)
    stat_w = (w - pad * 2 - int(24 * s)) // 2
    for i, (label, value, color) in enumerate([
        ("Influence", "4.1 / 5", INFLUENCE_WARM),
        ("Intellect (IQ)", "132", INTELLECT_COOL),
    ]):
        sx = pad + i * (stat_w + int(24 * s))
        rounded(draw, [sx, stats_y, sx + stat_w, stats_y + int(160 * s)], radius=int(20 * s), fill=CARD, outline=CARD_LINE, width=1)
        draw.text((sx + int(24 * s), stats_y + int(24 * s)), label, font=font(int(20 * s), bold=False), fill=TEXT_MUTED)
        draw.text((sx + int(24 * s), stats_y + int(56 * s)), value, font=font(int(44 * s)), fill=color)
        draw.text((sx + int(24 * s), stats_y + int(118 * s)), "avg +8 · +3 today" if i == 0 else "avg +15 pts", font=font(int(16 * s), bold=False), fill=TEXT_MUTED)

    tp_y = stats_y + int(160 * s) + int(24 * s)
    rounded(draw, [pad, tp_y, w - pad, tp_y + int(110 * s)], radius=int(20 * s), fill=CARD, outline=CARD_LINE, width=1)
    draw.text((pad + int(24 * s), tp_y + int(20 * s)), "Thought Power balance", font=font(int(20 * s), bold=False), fill=TEXT_MUTED)
    draw.text((pad + int(24 * s), tp_y + int(50 * s)), "2,480 TP", font=font(int(36 * s)), fill=TEXT_WHITE)

    graph_y = tp_y + int(110 * s) + int(24 * s)
    if graph_y + int(220 * s) < h - int(40 * s):
        rounded(draw, [pad, graph_y, w - pad, graph_y + int(220 * s)], radius=int(20 * s), fill=CARD, outline=CARD_LINE, width=1)
        draw.text((pad + int(24 * s), graph_y + int(20 * s)), "Score history vs. platform average", font=font(int(20 * s), bold=False), fill=TEXT_MUTED)
        import random
        random.seed(7)
        pts = []
        gx0, gx1 = pad + int(24 * s), w - pad - int(24 * s)
        gy0, gy1 = graph_y + int(70 * s), graph_y + int(200 * s)
        n = 10
        val = 0.4
        for i in range(n):
            val = max(0.1, min(0.9, val + random.uniform(-0.15, 0.2)))
            x = gx0 + (gx1 - gx0) * i / (n - 1)
            y = gy1 - (gy1 - gy0) * val
            pts.append((x, y))
        draw.line([(gx0, (gy0 + gy1) / 2), (gx1, (gy0 + gy1) / 2)], fill=TEXT_MUTED, width=2)
        draw.line(pts, fill=INTELLECT_COOL, width=int(4 * s), joint="curve")

    watermark(img, draw, w, h, s, "Profile — Influence / Intellect scorecard")
    return img


def screen_quiz(w, h, s):
    img = gradient_bg(w, h, BG_DARK, (18, 24, 30))
    draw = ImageDraw.Draw(img)
    pad = int(48 * s)
    sheet_y = int(h * 0.22)
    rounded(draw, [0, sheet_y, w, h], radius=0, fill=CARD)
    draw.rectangle([0, sheet_y, w, sheet_y + int(28 * s)], fill=CARD)
    rounded(draw, [pad, sheet_y - int(10 * s), w - pad, sheet_y + int(300 * s)], radius=int(28 * s), fill=CARD, outline=CARD_LINE, width=1)

    draw.text((pad, int(80 * s)), "Daily Mission", font=font(int(48 * s)), fill=TEXT_WHITE)
    draw.text((pad, int(150 * s)), "Question 2 of 3", font=font(int(22 * s), bold=False), fill=TEXT_MUTED)

    # timer ring
    ring_d = int(100 * s)
    rx, ry = w - pad - ring_d, int(70 * s)
    draw.ellipse([rx, ry, rx + ring_d, ry + ring_d], outline=INFLUENCE_WARM, width=int(8 * s))
    draw.arc([rx, ry, rx + ring_d, ry + ring_d], start=-90, end=170, fill=ACCENT_BLUE, width=int(8 * s))
    draw.text((rx + int(28 * s), ry + int(32 * s)), "12s", font=font(int(24 * s)), fill=TEXT_WHITE)

    q_y = int(220 * s)
    bar_placeholder(draw, pad, q_y, w - pad * 2, int(24 * s), CARD_LINE)
    bar_placeholder(draw, pad, q_y + int(36 * s), int((w - pad * 2) * 0.7), int(24 * s), CARD_LINE)

    opt_y = sheet_y + int(40 * s)
    labels = ["A", "B", "C", "D"]
    correct_idx = 1
    for i, lab in enumerate(labels):
        oy = opt_y + i * int(80 * s)
        color = TRUTH_GREEN if i == correct_idx else CARD_LINE
        rounded(draw, [pad, oy, w - pad, oy + int(64 * s)], radius=int(18 * s), fill=(30, 32, 44), outline=color, width=int(3 * s))
        draw.text((pad + int(20 * s), oy + int(16 * s)), lab, font=font(int(24 * s)), fill=TEXT_WHITE)
        bar_placeholder(draw, pad + int(64 * s), oy + int(22 * s), int(240 * s), int(20 * s), CARD_LINE)
        if i == correct_idx:
            cx0, cy0 = w - pad - int(46 * s), oy + int(34 * s)
            cw = int(9 * s)
            draw.line([cx0 - cw, cy0, cx0, cy0 + cw], fill=TRUTH_GREEN, width=max(2, int(4 * s)))
            draw.line([cx0, cy0 + cw, cx0 + cw * 2, cy0 - cw * 1.4], fill=TRUTH_GREEN, width=max(2, int(4 * s)))

    feedback_y = opt_y + 4 * int(80 * s) + int(30 * s)
    if feedback_y + int(70 * s) < h:
        rounded(draw, [pad, feedback_y, w - pad, feedback_y + int(70 * s)], radius=int(18 * s), fill=TRUTH_GREEN)
        draw.text((pad + int(24 * s), feedback_y + int(20 * s)), "Correct! +5 TP", font=font(int(24 * s)), fill=(15, 40, 25))

    watermark(img, draw, w, h, s, "Daily quiz — instant correct/incorrect feedback")
    return img


SCREENS = [
    ("01_feed", screen_feed),
    ("02_discover_truth_vote", screen_discover),
    ("03_profile_scorecard", screen_profile),
    ("04_daily_quiz", screen_quiz),
]


def render_set(out_dir, w, h, scale):
    for name, fn in SCREENS:
        img = fn(w, h, scale)
        path = os.path.join(out_dir, f"{name}.png")
        img.save(path)
        print("wrote", path, img.size)


if __name__ == "__main__":
    # Phone: 1080x1920 (9:16), within 320-3840px per side.
    render_set(OUT_PHONE, 1080, 1920, scale=1.0)
    # 7-inch tablet: 1200x1920 (9:16), within 320-3840px per side.
    render_set(OUT_TABLET7, 1200, 1920, scale=1.111)
    # 10-inch tablet: 1600x2560 (9:16), within 1080-7680px per side.
    render_set(OUT_TABLET10, 1600, 2560, scale=1.481)
