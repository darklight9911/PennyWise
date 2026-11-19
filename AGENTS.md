# pennyWise – instructions for AI agents (Antigravity)

pennyWise is a free, offline-first personal finance app for Android (Play
Store first, iOS later). Flutter app in `mobile/`, Go API and worker in
`backend/`, PostgreSQL + Redis, receipts and exports in Cloudflare R2.

- Product plan, design rules and milestone status: [PLAN.md](PLAN.md)
  (section 8 is the source of truth for what is done and what is open).
- How to run things locally: [README.md](README.md).
- Production server: [deploy/README.md](deploy/README.md).
  Play Store release: [docs/RELEASE.md](docs/RELEASE.md).
- [CLAUDE.md](CLAUDE.md) is the same guide for Claude Code.
  When you change project facts or rules here, update CLAUDE.md too.
- To pick the next task, run the `/next-step` workflow
  (`.agents/workflows/next-step.md`).

## Where the project stands (2026-11-19)

All feature milestones (0–8) are built on both the server and the phone.
What is left, in order:

1. **Milestone 9, release.** Owner-only steps: email provider, domain
   (fill the `[...]` placeholders in `deploy/site/*.html`), Play Console,
   closed test with 12 testers for 14 days. See docs/RELEASE.md.
2. **Firebase push** (open part of Milestones 4 and 5). Budget alerts and
   recurring reminders are only logged until a Firebase project exists.
   Needs the owner to create the project; never commit `google-services.json`.
3. **Real-phone checks** for app lock, camera and gallery (receipts).
   No Android SDK or phone is attached to this machine.

Before suggesting new work, read PLAN.md section 8 and the latest
`git log`; they may have moved on since this file was written.

## How to decide what to do next

1. `git status` and `git log --oneline -15`: finish or ask about any
   half-done work first (it may belong to another agent session).
2. PLAN.md section 8: the first row that is not ✅ is the current
   milestone. Its **Open** part says what is missing.
3. If the open items need the owner (accounts, domains, keys, a real
   phone), do not fake them. Say what the owner must do, step by step,
   and offer work you can do meanwhile.
4. Otherwise pick the smallest useful chunk, make a short plan, then build
   it with its tests and commit it (rules below).
5. Never add features outside PLAN.md without asking the owner first.

## Product decisions (do not re-open unless the user asks)

- Free: no ads, no billing, no `plan` field. Login: email/password + Google.
  No Sign in with Apple, no Resend, no Sentry/uptime service for now
  (the user declined these; Prometheus `/metrics` stays).
- Palette: primary #2C706E, secondary #729D99 (fills only, never text),
  canvas #EEE9E0, income #388D3D (large text, icons, charts),
  incomeText #2F7734 (small text), expense #BA1120. Dark mode exists.
- Font **Onest** (bundled in `mobile/assets/fonts/onest/`), body 16/24,
  text #000000DE. Icons: **Hugeicons** only, through `AppIcon`
  (`lib/core/widgets/app_icon.dart`); never Material `Icons.*`.
- Mascot **Penny** the panda: Rive file `assets/rive/penny.riv`, built
  from `mobile/rive/` (see its README for the artboard contract).
- The confirm-email reminder lives in Settings, not on the dashboard.

## Rules that must not break (details in PLAN.md section 3)

- Money is BIGINT minor units with an ISO currency next to it; never float.
  Store the exchange rate used on each transaction.
- Offline-first: the phone writes to its encrypted local Drift DB
  (SQLite3MultipleCiphers, key in secure storage) and syncs through an
  outbox. Row IDs are client UUIDv7, deletes are soft, sync versions are
  per user (`users.sync_version`), push is idempotent, last write wins.
- Recurring occurrences use `UUIDv5(rule_id:date)` on phone and server.
- Months, budgets and reports use `local_date`, never the UTC date.
- Receipts never pass through the API: presigned R2 PUT, then a HEAD check.
- No user enumeration on auth routes; rate limits on every route.

## Layout

- `backend/cmd/{api,worker,migrate}`, `backend/internal/<feature>`
  (auth, datasync, fx, receipts, reports, exports, recurring, notify,
  audit, account, …), `backend/migrations` (goose, embedded),
  `backend/queries` + `sqlc.yaml` → `internal/db` (generated, never edit).
- `mobile/lib/core` (theme, router, network, database, widgets) and
  `mobile/lib/features/<feature>/{application,data,domain,presentation}`.
  Drift code (`*.g.dart`) is generated: `dart run build_runner build`.
- `deploy/` production compose (Caddy HTTPS, backups) and `deploy/site/`
  privacy and account-deletion pages. CI: `.github/workflows/{api,mobile,deploy}.yml`.

## Git: commit in small chunks, push after every change

- **Never put all changes in one commit.** Split the work into small, logical
  commits, one chunk at a time, each with a clear message. Examples of one chunk:
  - a database migration and its queries
  - one backend package with its tests
  - one screen or one widget with its tests
  - config / CI / docs changes
- Each commit must build and pass its tests on its own. Put tests in the same
  commit as the code they test.
- Commit and push to `origin main` after every change, without asking first.
  The repository is **public**.
- Do not add a Claude `Co-Authored-By` line to your own commits.
- Commits use the repo-local GitHub noreply email
  (`git config user.email` in this repo). Never commit with a personal email.
- Another session may have uncommitted work in the same folder. Never
  commit or rewrite files you did not change; check `git status` first.

## Before every push

1. Run the checks for what changed:
   - Backend (in `backend/`): `make lint` and `make test`
     (integration tests run when `TEST_DATABASE_URL` / `TEST_REDIS_URL` are set in `.env`).
     After editing `queries/*.sql`, run `make sqlc` and commit the result.
   - Mobile (in `mobile/`): `dart format --output=none --set-exit-if-changed lib test`,
     `flutter analyze`, `flutter test`. After changing Drift tables, run
     `dart run build_runner build --delete-conflicting-outputs`.
2. Scan the staged diff for secrets and private data: API keys, tokens,
   private keys, passwords (other than the local dev placeholders), Google
   client IDs, personal emails, home-folder paths.
   The system `grep` is ugrep and rejects long patterns, so scan with Python
   `re` or `git grep`, and never trust a scan that printed an error.
3. Never commit `.env`, keystores, `key.properties`, `google-services.json`
   or other credential files.
4. After changing pubspec plugins or anything in `android/` or `ios/`, check
   the `build-android` job of the `mobile` CI run before calling it done:
   only CI builds the Android release.

## Toolchain notes

- Go and Flutter live in `~/.local/opt/go/bin` and `~/.local/opt/flutter/bin`
  (add them to `PATH` in each shell).
- Postgres and Redis: `docker compose up -d`. If Docker says it cannot
  reach `~/.docker/desktop/docker.sock`, use the system daemon:
  `export DOCKER_HOST=unix:///var/run/docker.sock`.
- No Android SDK and no Linux desktop toolchain on this machine.
- The app cannot run as-is on the web: the encrypted database needs
  `dart:ffi`. A web preview needs a scratch copy with an in-memory database,
  never committed.
