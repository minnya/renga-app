# how-to: Playwright E2E scenario testing against this Flutter web app

reusable methodology, not tied to one feature. Read this before any future "test X with Playwright" task.

## constraints (why this isn't a normal web Playwright setup)
- Flutter web renders to `<canvas>` (CanvasKit) by default -> no queryable DOM/ARIA tree until semantics is enabled.
- No Docker available in this environment -> `supabase start` (local stack) cannot run. All testing hits the
  **real remote/production** Supabase project (`chat-app-backend`, ref `runztxxvrjlpebecnkgt`). Treat every
  action as touching prod data; clean up test rows afterward.
- Signup requires email confirmation (`supabase/config.toml` `[auth.email] enable_confirmations = true`,
  Resend SMTP configured) — a plain signup does not immediately produce a usable session.

## 1. build & serve
```
flutter build web --release -t lib/main.dart
(cd build/web && python -m http.server 8766 &)
```
Rebuild + re-serve (kill previous `http.server` first) after every code change under test — this is a static
build, not hot-reload.

## 2. driving the app: playwright-cli
Use the `playwright-cli` skill. No global install here -> prefix every call with `npx playwright cli ...`
(confirmed working; `npx playwright-cli` alone is not installed globally).

```
npx playwright cli open http://localhost:8766
```

### enable accessibility (required every fresh page load / reload)
Flutter injects an offscreen `<flt-semantics-placeholder>` that must be clicked to turn on the semantics tree.
It sits outside the viewport, so a normal `click <ref>` times out ("element is outside of the viewport").
Use `run-code` to click it via `evaluate` instead:
```
npx playwright cli run-code "async page => { await page.evaluate(() => { document.querySelector('flt-semantics-placeholder').click(); }); }"
```
After this, `npx playwright cli snapshot` returns a normal ARIA tree (`getByRole`, text, etc. all work).
Must be redone after every full page reload/navigation-via-`goto` to a fresh document (SPA route pushes via
in-app buttons/links do NOT reset it, only real navigations do).

### timer-gated quiz questions: CLI spawn overhead beats short timers
Onboarding questions have a 5s timer; daily quiz questions ~17-90s. Each separate `npx playwright cli <cmd>`
invocation costs ~1-3s of Node/IPC startup, so two round trips (snapshot, then click) can blow a 5s window.
Fixes:
- Prefer one `run-code` call combining "wait for element by role" + "click" in a single script instead of
  snapshot-then-click-by-ref for anything time-sensitive:
  ```
  npx playwright cli run-code "async page => { await page.getByRole('button', { name: /Next|See Results/ }).click({timeout: 15000}); }"
  ```
- If a 5s-timer question is missed anyway, that's fine — the timeout path (`_handleAnswer(null)`) is itself
  worth exercising; just click through the resulting "Incorrect" feedback overlay same as a wrong answer.

## 3. getting a usable logged-in test account
No test account backdoor exists in the app (checked: no debug flag skips onboarding/profile-completion).
Signing up with a fake domain (`@example.com`) makes the Auth API 500 with
`{"code":"unexpected_failure","message":"Error sending confirmation email"}` and the user is **not created at
all** (transaction rolled back) — do not use fake domains.

Working recipe:
1. Sign up through the UI with email **`delivered@resend.dev`** (Resend's always-accepts-delivery sandbox
   address — confirmed working, signup returns 200). Pick any password/username.
2. The app shows a "check your inbox" dialog — there is no real inbox to check. Instead confirm the email
   directly against the linked prod DB via the Supabase CLI (already authenticated/linked in this environment,
   confirmed via `npx supabase projects list`):
   ```
   npx supabase db query --linked "update auth.users set email_confirmed_at = now() where email = 'delivered@resend.dev' returning id, email, email_confirmed_at"
   ```
   `--linked` is required — plain `supabase db query` defaults to a local DB that doesn't exist here.
3. Dismiss the dialog, log in normally with that email/password.
4. Fresh account -> router redirects to `/onboarding-quiz` automatically; complete it (any answers) to reach
   the main app / `/daily-quiz`.

`delivered@resend.dev` is a single fixed address — only one live test account can exist under it at a time.

## 4. cleanup (do this at the end of every test session)
Delete the throwaway user so prod doesn't accumulate test accounts/posts:
```
npx supabase db query --linked "delete from auth.users where id = '<uuid>' returning id"
```
Deleting from `auth.users` cascades to `profiles`/`quiz_responses`/etc (FK cascade) — confirmed working.
Also remove local scratch: `.playwright-cli/` directory, `npx playwright cli close`, kill the `http.server`.

## 5. inspecting network/errors during a run
`npx playwright cli console error` and `npx playwright cli requests` / `request <n>` /
`response-body <n>` are the primary tools for catching real bugs (e.g. this is how the
`award_daily_completion_tp` RPC 400-on-retry bug was found — see
`design/ai/daily_quiz_result_tp_award_failure.md`). Expect noisy, irrelevant
`accounts.google.com/gsi/button 403` / `GSI_LOGGER` errors on every page (Google Sign-In client ID isn't
authorized for `localhost` origins) — not a real bug, ignore them.
