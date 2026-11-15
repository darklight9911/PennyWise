# pennyWise – instructions for Claude

Personal finance app: Flutter (`mobile/`) + Go API (`backend/`) with PostgreSQL and Redis.
The full plan is in [PLAN.md](PLAN.md). How to run things is in [README.md](README.md).

## Git: commit in small chunks, push after every change

- **Never put all changes in one commit.** Split the work into small, logical
  commits, one chunk at a time, each with a clear message. Examples of one chunk:
  - a database migration and its queries
  - one backend package (e.g. password hashing) with its tests
  - one screen or one widget with its tests
  - config / CI / docs changes
- Each commit must build and pass its tests on its own. Put tests in the same
  commit as the code they test.
- Commit and push to `origin main` after every change, without asking first.
  The repository is **public**.
- End every commit message with:
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`
- Commits use the repo-local GitHub noreply email
  (`git config user.email` in this repo). Never commit with a personal email.

## Before every push

1. Run the checks for what changed:
   - Backend (in `backend/`): `make lint` and `make test`
     (integration tests run when `TEST_DATABASE_URL` / `TEST_REDIS_URL` are set in `.env`).
   - Mobile (in `mobile/`): `dart format --output=none --set-exit-if-changed lib test`,
     `flutter analyze`, `flutter test`.
2. Scan the staged diff for secrets and private data: API keys, tokens,
   private keys, passwords (other than the local dev placeholders), Google
   client IDs, personal emails, home-folder paths.
   The system `grep` is ugrep and rejects long patterns, so scan with Python
   `re` or `git grep`, and never trust a scan that printed an error.
3. Never commit `.env`, keystores, `key.properties`, `google-services.json`
   or other credential files.

## Toolchain notes

- Go and Flutter live in `~/.local/opt/go/bin` and `~/.local/opt/flutter/bin`
  (add them to `PATH` in each shell).
- Postgres and Redis run with `docker compose up -d`.
- No Android SDK on this machine: Android builds are checked by GitHub CI.
