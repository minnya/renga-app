# Play Store listing assets (English, generated from design/product.md §7)

- `short_description_en.txt` — 78 chars (limit 80)
- `full_description_en.txt` — 3,748 chars (limit 4000)
- `app_icon_512.png` — 512x512, resized from `assets/icon/renga_icon_1024.png` (final art, not a placeholder)
- `../screenshots_en/phone/*.png` — 1080x1920 (9:16)
- `../screenshots_en/tablet_7in/*.png` — 1200x1920 (9:16)
- `../screenshots_en/tablet_10in/*.png` — 1600x2560 (9:16)

Screenshots are **real in-app captures**, composited onto a branded
background with a short marketing caption:

1. `capture_screenshots.js` — drives `flutter build web --release` via
   Playwright's device emulation (Pixel 7 / Galaxy Tab S4 / Galaxy Tab S9 —
   the programmatic equivalent of Chrome DevTools' device toolbar) against a
   logged-in test account on the production Supabase project. Raw captures
   land in `raw/<size>/*.png` (git-ignored).
2. `compose_screenshots.py` — composites each raw capture onto a
   brand-gradient background (design/system.md palette) with a bold
   marketing caption and a rounded, drop-shadowed device frame, writing the
   final images to `../screenshots_en/<size>/`.

See design/product.md §7 for known content-quality caveats in the raw
captures (test post copy, UUID-based profile handle) to revisit once real
user content is available.

`generate_screenshots.py` still exists to regenerate the older
PLACEHOLDER MOCKUP wireframes used only by the landing page
(`assets/store/screenshots/`), not by the Play Console listing.
