---
layout: default
title: Renga — Account Deletion
---

# Account Deletion

**Last updated: July 13, 2026**

This page explains how to request deletion of your Renga account and the data associated with it.
Renga is developed and operated by minnya ("Developer"). It should be read together with our
[Privacy Policy](privacy.html) and [Terms of Service](terms.html).

## How to Delete Your Account

### Option 1: In-app (recommended)

1. Open the Renga app and sign in.
2. Go to **Settings**.
3. Tap **Delete Account**.
4. Read the warning, then re-enter your username to confirm.
5. Tap the **Delete Account** button.

Your account is deleted immediately — there is no waiting period. You will be signed out and
returned to the login screen once deletion completes.

### Option 2: By email (if you cannot access the app)

If you are unable to sign in (e.g., you lost access to your device or your account is suspended),
you can request deletion by emailing **[support@renga-app.com](mailto:support@renga-app.com)** from
the email address associated with your account, with the subject line "Account Deletion Request" and
your username. We will verify your identity and delete your account within a reasonable timeframe,
generally within 30 days.

## What Data Is Deleted

Deleting your account permanently removes:

- Your login credentials and account record (email, password/Google sign-in link).
- Your profile: username, display name, avatar, bio, and any other profile fields.
- Your Influence and Intellect scores, score history, TP balance, and ticket/wager data.
- Your posts, comments, replies, likes, and reactions.
- Your direct messages and conversations (both sides of a conversation are removed when both
  participants have deleted their accounts; see retention note below).
- Your blocks/blocked-by relationships.
- Your device push-notification token.

This data is removed from our production database (Supabase) generally within 30 days of your
deletion request being processed. Because posts, comments, and messages are linked to your account
by foreign key and cascade on account deletion, they are removed automatically alongside your
account — there is no separate step to request content deletion.

## What Data May Be Retained

Some data may be retained for a limited additional period, or longer where required by law, to
protect the safety and integrity of the platform:

- **Moderation records**: reports you filed or that were filed against your content, and any strike
  history, may be retained after account deletion to prevent abuse of the reporting/strike system
  (e.g., re-registration to evade a ban) and for legal/compliance purposes.
- **Aggregated or de-identified analytics**: usage and crash data that has already been aggregated or
  stripped of identifiers (via Firebase Analytics/Crashlytics) is not personally linked to you and is
  not deleted, since it no longer identifies you.
- **Backups**: your data may persist in encrypted database backups for a limited period (up to 30
  days) before being purged as part of routine backup rotation.
- **Legal holds**: if we are required to preserve data by law, subpoena, or an active legal
  investigation, we will retain the minimum necessary data until that obligation ends.

## Contact

Questions about account deletion can be sent to
**[support@renga-app.com](mailto:support@renga-app.com)**.

---

*This document is a functional starting template prepared for Renga's initial release and has not
been reviewed by a lawyer. Please have it reviewed by qualified legal counsel before relying on it
for a public app store submission.*
