# Play Store listing assets (English, generated from design/product.md §7)

- `short_description_en.txt` — 78 chars (limit 80)
- `full_description_en.txt` — 3,748 chars (limit 4000)
- `app_icon_512.png` — 512x512, resized from `assets/icon/renga_icon_1024.png` (final art, not a placeholder)
- `../screenshots_en/phone/*.png` — 1080x1920 (9:16)
- `../screenshots_en/tablet_7in/*.png` — 1200x1920 (9:16)
- `../screenshots_en/tablet_10in/*.png` — 1600x2560 (9:16)

Screenshots are **real in-app captures** (Feed, Discover Truth Vote, Profile
scorecard, Daily Quiz), taken from `flutter build web --release` driven by
Playwright against a logged-in test account on the production Supabase
project. See design/product.md §7 for known content-quality caveats (test
post copy, UUID-based profile handle) to revisit once real user content is
available.

`generate_screenshots.py` still exists to regenerate the older
PLACEHOLDER MOCKUP wireframes used only by the landing page
(`assets/store/screenshots/`), not by the Play Console listing.
