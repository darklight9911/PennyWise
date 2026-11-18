# pennyWise: Project Plan

An all-in-one personal finance app for Android and iOS, with a Go backend.
Target: publish on the Google Play Store (App Store later).

---

## 1. Product scope (v1)

| Area | v1 features |
|---|---|
| **Accounts** | Multiple accounts (cash, bank, card, e-wallet, savings). Each account has its own currency. Live balance. |
| **Transactions** | Income, expense and transfer between accounts. Category, note, date, tags. Search and filter. |
| **Receipts** | Attach up to 3 receipt photos per transaction (camera or gallery). Compressed on the phone, stored in Cloudflare R2. |
| **Categories** | Default set plus user-made categories with icon and colour. One level of sub-categories. |
| **Budgets** | Monthly (or weekly) limit per category or overall. Push alerts at 80% and 100%. |
| **Goals** | Savings goals with a target amount, a deadline and contributions. Progress bar. |
| **Recurring** | Recurring bills, subscriptions and salary (daily, weekly, monthly, yearly). Reminders before the due date. |
| **Reports** | Spending by category (pie), income vs expense (bar), trend over time (line), cash flow per month. |
| **Export** | CSV and PDF export for a date range. |
| **Multi-currency** | Base currency per user. Daily exchange rates from Frankfurter (ECB data, about 30 currencies). For a currency Frankfurter does not cover, the user types the rate by hand on the transaction. Totals converted to the base currency. |
| **Auth** | Email + password (with verification and reset) and Google Sign-In. |
| **Security** | Optional app lock (PIN or biometric). HTTPS for all traffic. **Encrypted local database** on the phone. Delete-account option (required by Play). |

**Not in v1** (later versions): bank or SMS auto-import, shared/family budgets, AI insights, web dashboard, iOS release.

**Business model:** completely free. No ads, no subscriptions, no in-app purchases. So there is no `plan` field and no Play Billing.

---

## 2. Tech stack

### Mobile (Flutter)
| Concern | Choice | Why |
|---|---|---|
| Language | Dart 3, Flutter stable | One codebase for Android and iOS |
| State management | **Riverpod** | Testable, no BuildContext tricks |
| Navigation | **go_router** | Deep links, auth redirects |
| Local database | **Drift** (SQLite) + **SQLite3MultipleCiphers** (`package:sqlite3` with `source: sqlite3mc`) | Offline-first: the UI reads local data. The whole database file is encrypted with a random 256-bit key kept in the Keystore/Keychain, so finance data is unreadable if the phone is rooted or a copy leaks. Chosen over the SQLCipher build because it tracks current SQLite and needs no OpenSSL (it can still read SQLCipher-format files). One owner per phone: logout, or a different user logging in, wipes the data and its key |
| Networking | **Dio** + interceptors | Token refresh, retries |
| Models | **freezed** + json_serializable | Immutable models, less boilerplate |
| Charts | **fl_chart** | Pie, bar and line charts |
| Secure storage | flutter_secure_storage | Tokens and PIN hash |
| Biometrics | local_auth | App lock |
| Push | firebase_messaging (FCM) | Budget and bill alerts |
| Auth | google_sign_in | The ID token is verified by the backend |
| i18n | flutter_localizations + intl | Currency and date formatting |
| Crash reporting | Firebase Crashlytics | Free, and Firebase is already used for push |
| DB encryption key | flutter_secure_storage | A random 256-bit key is made on first launch and kept in the Android Keystore / iOS Keychain, never in code |
| Receipt photos | image_picker + flutter_image_compress | Pick or take a photo, shrink it to about 1600 px JPEG before upload |

### Backend (Go)
| Concern | Choice | Why |
|---|---|---|
| Language | Go 1.23+ | Fast, simple to deploy |
| HTTP router | **chi** | Small, idiomatic, works with net/http |
| DB driver | **pgx v5** | Fastest Postgres driver |
| Queries | **sqlc** | Type-safe Go generated from SQL |
| Migrations | **goose** (or golang-migrate) | Versioned schema changes |
| Cache / queues | **Redis** | Rate limiting, refresh-token denylist, rate cache, job queue |
| Background jobs | **asynq** (on Redis) | Recurring transactions, alerts, exports, FX fetch |
| Object storage | **Cloudflare R2** via aws-sdk-go-v2 (S3 API) | Receipts, export files, DB backups. 10 GB free, no fees to download files |
| FX rates | **Frankfurter** API (api.frankfurter.app) | Free, no key, daily ECB rates |
| Auth | JWT access (15 min) + rotating refresh tokens (30 days) | Stateless API, revocable sessions |
| Passwords | argon2id | Current best practice |
| Validation | go-playground/validator | Request validation |
| Config | env vars (envconfig) | 12-factor |
| Logging | slog (JSON) | Built-in, structured |
| API docs | OpenAPI 3 spec | Can also generate the Dart client |
| Observability | Prometheus metrics + OpenTelemetry traces | Production readiness |
| Testing | testcontainers-go (real Postgres/Redis) | Reliable integration tests |

### Infrastructure
- **Docker Compose** for local development (api, worker, postgres, redis).
- **Production (budget about $5–15 a month)**: one VPS, e.g. Hetzner CX22 (2 vCPU, 4 GB RAM, about €4–5) or similar. Docker Compose runs `caddy`, `api`, `worker`, `postgres` and `redis` on it.
  - Caddy is the reverse proxy and gets HTTPS certificates automatically.
  - Postgres and Redis are **not** exposed to the internet. Only ports 80 and 443 are open (ufw firewall, SSH by key only).
  - Postgres tuned for 4 GB RAM (`shared_buffers=1GB`, `effective_cache_size=3GB`). Redis with AOF persistence and a `maxmemory` limit.
  - Cloudflare in front for DNS (free).
- **CI/CD**: GitHub Actions. Lint, test and build for the Go API, then push the image to GHCR and deploy over SSH. Analyze, test and build the AAB for Flutter. Fastlane for Play Store upload.
- **Backups** (we manage these ourselves, because the database is self-hosted):
  - Nightly `pg_dump` (compressed), uploaded to a private R2 bucket. Keep 7 daily, 4 weekly and 6 monthly copies.
  - WAL archiving with **WAL-G** to R2 for point-in-time recovery (lose at most a few minutes of data).
  - **Test a restore every month.** A backup that was never restored is not a backup.
- **Upgrade path**: when users grow, move Postgres to a managed service first. The app needs no code change, only a new `DATABASE_URL`.

---

## 3. Architecture

```
┌──────────────────────┐        HTTPS/JSON        ┌───────────────────────────┐
│   Flutter app        │ ───────────────────────► │  Go API (chi)             │
│  UI ─ Riverpod       │                          │  handlers → services →    │
│  Repository layer    │ ◄─────────────────────── │  repositories (sqlc/pgx)  │
│  Drift (SQLite)      │      /sync push/pull     └──────┬──────────┬─────────┘
│  Sync engine         │                                 │          │
└──────────────────────┘                          ┌──────▼───┐  ┌───▼─────┐
          ▲                                       │PostgreSQL│  │  Redis  │
          │ FCM push                              └──────▲───┘  └───▲─────┘
          │                                              │          │
   ┌──────┴──────┐                                ┌──────┴──────────┴──┐
   │ Firebase    │ ◄───────────────────────────── │ Worker (asynq)     │
   │ Cloud Msg.  │                                │ recurring, alerts, │
   └─────────────┘                                │ FX rates, exports  │
                                                  └────────────────────┘
```

### Offline-first sync (important design decision)
People log expenses anywhere, often with no signal. So:
1. The app writes to the local Drift DB first. The UI updates at once.
2. Every row has a **client-generated UUID v7** and an `updated_at`. Deletes are **soft deletes** (`deleted_at`).
3. Changes go into an outbox. The sync engine pushes them to `POST /v1/sync/push` when online.
4. The app pulls changes with `GET /v1/sync/pull?since=<version>`. Every synced row has a `version` number, and the app remembers the highest one it has seen.
   - **Do not use one shared Postgres sequence** for `version`. Two saves can take numbers 10 and 11, and save 11 can finish first. A phone that pulls in between gets 11, moves past 10 and **never downloads row 10**.
   - Instead, each user has their own counter, `users.sync_version`. Every push starts with `UPDATE users SET sync_version = sync_version + 1 … RETURNING sync_version`. This locks that user's row, so one user's saves happen one after another and their version numbers always finish in order. Different users still save in parallel.
5. Conflicts: **last write wins** by `updated_at`, per row. This is enough for a single-user finance app. The server never accepts an `updated_at` more than 5 minutes in the future, because a phone with a wrong clock would otherwise win every conflict.
6. Push is **idempotent** (safe to repeat). Rows are upserted by their UUID, so a batch sent twice after a timeout changes nothing the second time.

### Receipt upload flow
Photos never pass through the Go API. The API only signs the upload, so the small VPS is not loaded with images.
1. The app compresses the photo and saves it locally. It shows at once, even offline.
2. When online, the app calls `POST /v1/receipts/upload-url` with the file's size and type. The API checks them (JPEG/PNG, max 2 MB) and returns a **presigned PUT URL** for R2 that is valid for 5 minutes. The size and type are part of the signature, so the app cannot upload a different or bigger file with that URL.
3. The app uploads the file straight to R2, then calls `POST /v1/receipts/{id}/confirm`. The API does **not** trust this call alone. It sends a `HEAD` request to R2 to check that the file exists and has the expected size, and only then marks the receipt `uploaded`.
4. **Clean-up:** a nightly worker job deletes receipts still `pending` after 24 hours, both the database row and any file in R2. These are uploads that were started but never finished.
5. To view a receipt, the app asks for a short-lived **presigned GET URL**. The bucket is private, never public.
6. Object key pattern: `receipts/{user_id}/{receipt_id}.jpg`. When a user deletes their account, a job deletes everything under their prefix.

### Money handling rules (do not break these)
- Store amounts as **BIGINT minor units** (cents), never float. Example: $12.34 → `1234`.
- Always store `currency` (ISO 4217) next to an amount. Handle currencies with 0 or 3 decimals (JPY, KWD).
- Store the **exchange rate used** on each transaction, so old reports stay stable when rates change.
- Balances are derived from transactions (plus an opening balance), not edited by hand.
- Budgets and goals are always in the user's **base currency**, so "spent vs limit" is a simple comparison.

### Changing the base currency
Each transaction stores `amount_base_minor`, its amount converted to the base currency. If the user switches base currency (say USD → EUR), all those stored values become wrong.
1. The app asks for confirmation, then sends the change.
2. The server sets `users.base_currency_status = 'recalculating'` and queues a worker job.
3. The job recomputes `fx_rate_to_base` and `amount_base_minor` for every transaction, using the rate **on that transaction's date**. Manual rates (`fx_rate_source = manual`) are converted through the old base currency, so the user's typed rate is kept. Budget and goal amounts are converted at today's rate.
4. The job works in batches of about 1,000 rows. Each batch bumps the sync version, so phones download the new values.
5. Until it finishes, the app shows "Recalculating totals…" on reports and budgets instead of wrong numbers.

### Recurring transactions (no duplicates)
A recurring bill can be created in two places. The phone creates it when offline, and the server worker creates it on schedule. Without care, the user would see the same bill twice.
- Each occurrence gets a **fixed ID worked out from the rule and the date**: `UUIDv5(namespace, rule_id + ":" + occurrence_date)`.
- The phone and the server always compute the same ID for the same occurrence. Sync upserts by ID, so the two copies merge into one row.
- If the user deletes one occurrence, the soft-deleted row keeps its ID. So neither side creates it again.
- `next_run_at` moves forward only after the occurrence is saved.

### Dates and time zones
"Which month does this expense belong to?" depends on the user's time zone. An expense at 23:30 on 31 March in New York is already 1 April in UTC.
- Each transaction stores `occurred_at` (`timestamptz`, the exact moment) **and** `local_date` (the calendar date where the user was, taken from the phone).
- Budgets, reports, "this month" and recurring due dates all use `local_date`, never the UTC date.
- `local_date` is fixed when the transaction is saved. If the user travels later, old expenses stay in the month they were made.

---

## 4. Database schema (PostgreSQL, first draft)

```
users              id, email, password_hash (nullable), google_sub (nullable),
                   name, base_currency, base_currency_status (ok|recalculating),
                   locale, timezone, email_verified_at,
                   sync_version BIGINT (per-user counter for sync),
                   created_at, updated_at, deleted_at
refresh_tokens     id, user_id, token_hash, device_name, expires_at, revoked_at
devices            id, user_id, fcm_token, platform, last_seen_at
accounts           id, user_id, name, type, currency, opening_balance,
                   icon, color, archived, version, updated_at, deleted_at
categories         id, user_id (null = default), parent_id, name, kind (income|expense),
                   icon, color, version, updated_at, deleted_at
transactions       id, user_id, account_id, category_id, kind (income|expense|transfer),
                   amount_minor, currency, fx_rate_to_base, amount_base_minor,
                   transfer_account_id, transfer_amount_minor,
                   occurred_at (timestamptz), local_date (date), note,
                   fx_rate_source (auto|manual),
                   recurring_id, occurrence_date, version, updated_at, deleted_at
receipts           id, user_id, transaction_id, object_key, content_type, size_bytes,
                   status (pending|uploaded), version, created_at, deleted_at
tags / transaction_tags
budgets            id, user_id, category_id (null = overall), amount_minor (base currency),
                   period (weekly|monthly), start_date, alert_thresholds int[], version, ...
goals              id, user_id, name, target_minor (base currency), deadline,
                   account_id (optional), version, ...
goal_contributions id, goal_id, amount_minor, occurred_at, ...
recurring_rules    id, user_id, template (jsonb), rrule, next_run_at,
                   remind_days_before, active, version, ...
exchange_rates     base, quote, rate, date   (PK: base, quote, date)
notifications      id, user_id, type, payload jsonb, sent_at, read_at
audit_log          id, user_id, action, entity, entity_id, at, ip
```

Key indexes: `transactions(user_id, local_date DESC)`, `transactions(user_id, category_id, local_date)`, `(user_id, version)` on every synced table, `receipts(status, created_at)` for the clean-up job.

Key constraints: `UNIQUE (recurring_id, occurrence_date)` on transactions, as a second guard against duplicate bills.

---

## 5. API (v1, REST)

```
POST   /v1/auth/register            POST /v1/auth/login
POST   /v1/auth/google              POST /v1/auth/refresh
POST   /v1/auth/logout              POST /v1/auth/verify-email
POST   /v1/auth/forgot-password     POST /v1/auth/reset-password

GET    /v1/me        PATCH /v1/me        DELETE /v1/me   (account deletion)
POST   /v1/devices                       (register FCM token)

POST   /v1/sync/push                     GET /v1/sync/pull?since=
GET|POST|PATCH|DELETE  /v1/accounts, /v1/categories, /v1/transactions,
                       /v1/budgets, /v1/goals, /v1/recurring
GET    /v1/reports/summary?from=&to=     GET /v1/reports/by-category
GET    /v1/reports/trend?interval=month
POST   /v1/exports  (csv|pdf)  →  GET /v1/exports/{id}
POST   /v1/receipts/upload-url       POST /v1/receipts/{id}/confirm
GET    /v1/receipts/{id}/url         DELETE /v1/receipts/{id}
GET    /v1/fx/rates?base=
GET    /healthz   /readyz   /metrics
```

Redis use: rate limits on auth endpoints (e.g. 5/min/IP), cached report summaries (invalidated on writes), cached FX rates, asynq job queue.

---

## 6. Repository layout

```
pennyWise/
├── PLAN.md
├── docker-compose.yml
├── .github/workflows/        api.yml, mobile.yml
├── backend/
│   ├── cmd/api/              main.go
│   ├── cmd/worker/           main.go
│   ├── internal/
│   │   ├── config/  http/ (router, middleware, handlers)
│   │   ├── auth/  accounts/  transactions/  budgets/  goals/
│   │   ├── recurring/  reports/  sync/  fx/  notify/  export/  receipts/  storage/
│   │   └── db/ (sqlc generated) 
│   ├── migrations/           goose SQL files
│   ├── queries/              sqlc .sql files
│   ├── api/openapi.yaml
│   └── Makefile
└── mobile/
    └── lib/
        ├── core/             theme, router, network, db, utils (money, dates)
        ├── features/
        │   ├── auth/  dashboard/  accounts/  transactions/
        │   ├── budgets/  goals/  recurring/  reports/  settings/
        │   └── (each: data/ domain/ presentation/)
        └── main.dart
```

---

## 7. Screens (mobile)

1. Onboarding (3 slides) → Sign up / Log in (email, Google) → choose base currency
2. **Dashboard**: total balance, this month income/expense, budget rings, recent transactions, quick-add FAB
3. Transactions list (grouped by day, filters, search) → Add/Edit transaction (amount keypad first)
4. Accounts list → account detail
5. Budgets → budget detail
6. Goals → goal detail + add contribution
7. Recurring / subscriptions
8. Reports (period switcher, charts) → Export
9. Settings: profile, currency, categories, app lock, notifications, theme (light/dark), delete account, privacy policy

---

## 7b. Visual design (clean minimal)

Style: light, calm and spacious. One accent colour. Numbers are the hero of each screen.

### Palette (given) and derived tokens

| Token | Hex | Use | Contrast check |
|---|---|---|---|
| `primary` | **#2C706E** | Buttons, FAB, active tab, links, key icons | 4.76:1 on canvas, white text on it 5.75:1 ✅ |
| `secondary` | **#729D99** | Chips, progress-bar fills, chart series, selected backgrounds | 2.48:1 on canvas ❌ for text, so **never use it for text or thin icons**. Use it as a fill with dark text on top (4.92:1 ✅) |
| `canvas` | **#EEE9E0** | Screen background | — |
| `surface` | #FBF9F5 (derived) | Cards, sheets, input fields, so they lift off the canvas | primary on it 5.47:1 ✅ |
| `onSurface` | #1F2A29 (derived) | Main text and amounts | 12.2:1 on canvas ✅ |
| `muted` | #5C6B69 (derived) | Secondary text, labels, dates | 4.62:1 on canvas ✅ |
| `income` | **#388D3D** (given) | Positive amounts, income chart bars, up-arrow icons. A brighter, purer green than `primary`, so it does not look like a button or link | 3.96:1 on surface, 3.44:1 on canvas. ✅ for large text (≥ 24 px, or ≥ 18.7 px bold) and icons. ⚠️ Below 4.5:1, so **not for small text** |
| `incomeText` | #2F7734 (derived) | Small income text: list amounts, labels, captions. Same hue as `income` (124°), only darker, so both read as one green | 5.24:1 on surface, 4.56:1 on canvas ✅ |
| `expense` | **#BA1120** (given) | Negative amounts, over-budget | 6.26:1 on surface, 5.45:1 on canvas ✅ |
| `outline` | #D9D2C5 (derived) | Dividers, card borders | — |

Rules:
- Never show income or expense by colour alone. Add a `+`/`−` sign as well, for colour-blind users.
- Chart colours: start from `primary` and `secondary`, then add further muted tones (to be picked in Milestone 0).
- Dark mode: planned for Milestone 8. It uses the same hue, with a dark green-grey canvas (about #141B1A).

### Type and spacing
- Font: **Inter** (or the system font). Amounts use **tabular figures**, so digits line up in lists.
- Spacing scale: 4, 8, 12, 16, 24, 32. Card radius 16, button radius 12.
- Built with Material 3 `ThemeData`, using a `ColorScheme` filled from the tokens above (not generated from a seed colour).

---

## 8. Milestones

| # | Milestone | Main output | Est. |
|---|---|---|---|
| 0 ✅ | Setup | Repo, Docker Compose, CI skeleton, Flutter project, design tokens | 3 days |
| 1 ✅ | Auth | Register/login/Google, JWT + refresh, email verification, encrypted local DB, app shell | 1 week |
| 2 ✅ | Core data | Accounts, categories, transactions (sync-only server path + local DB + UI), default categories, dashboard | 2 weeks |
| 2b ✅ | Receipts | Receipts table, presigned PUT/GET (type and size signed), HEAD check on confirm, nightly clean-up, receipts in sync pull; phone: attach from camera or gallery (also offline), upload after sync, full-screen view and delete | 4 days |
| 3 ✅ | Sync | Outbox, push/pull with per-user versions, conflict handling, idempotent push, offline and race-condition tests (built together with Milestone 2) | 1.5 weeks |
| 4 🟡 | Budgets + alerts | Budgets (sync, screens, dashboard), worker job with once-per-period alerts, device registration. **Open:** real FCM delivery and the phone's push registration need a Firebase project (alerts are logged until then) | 1 week |
| 5 🟡 | Goals + recurring | Goals with contributions, recurring rules with deterministic occurrence IDs generated on the phone and the server (15-minute worker job), reminders, screens for both. **Open:** reminders are logged until Firebase push is set up | 1 week |
| 6 ✅ | Multi-currency | exchange_rates (Frankfurter, every 6 h, backfill), base amounts by the rate of the day or a typed rate, fill job, base-currency change job, GET /v1/fx/rates; phone: main-currency change with "Recalculating totals" banner, typed rate on foreign transactions, totals in every currency, total balance converted at today's rate | 1 week |
| 7 ✅ | Reports + export | /v1/reports (summary, by category, trend), CSV and PDF export jobs into R2; phone: Reports screen (totals, spending ring, 6-month in/out bars, offline from the local database) and Export screen | 1 week |
| 8 🟡 | Polish + security | **Done:** audit log, per-IP and per-user rate limits on every route, account deletion (API + phone + erase job). **Open:** app lock, dark mode, a11y pass | 1 week |
| 9 🟡 | Release | **Done:** production compose with Caddy HTTPS, backups, release signing, privacy and deletion pages, docs/RELEASE.md. **Open (owner):** email provider, domain, Play Console steps, closed test | 1–2 weeks |

Total: about 12–13 weeks for one developer (sum of the rows above, 5 working days a week).

---

## 9. Play Store checklist

- [ ] Google Play developer account ($25 one-time)
- [ ] App signing with Play App Signing, release built as **AAB**
- [ ] Target the latest required API level
- [ ] Confirm the name "pennyWise" is free on the Play Store and the domain is available
- [ ] **Privacy policy URL** (hosted; page ready in `deploy/site/`) and **Data safety form** (answers in `docs/RELEASE.md`) (finance data, email, photos/receipts, device IDs; no crash SDK yet; no ads, no data sold)
- [x] **In-app account deletion + a web deletion link** (required by Play; web page in `deploy/site/`)
- [ ] Financial features declaration (personal finance tracker, no lending)
- [ ] **Closed testing with at least 12 testers for 14 days** (required for new personal developer accounts)
- [ ] Store listing: icon 512px, feature graphic 1024×500, at least 4 phone screenshots, short and full description
- [ ] Content rating questionnaire
- [ ] Production backend on HTTPS with a stable domain

---

## 10. Decisions log (2026-11-15)

| # | Question | Decision | Effect on the plan |
|---|---|---|---|
| 1 | App name | **pennyWise** is final | Check Play Store and domain availability before Milestone 9 |
| 2 | Visual style | **Clean minimal**, palette #2C706E / #729D99 / #EEE9E0, income #388D3D (large/icons) + #2F7734 (small text), expense #BA1120 | Section 7b. #729D99 is used only for fills, never for text |
| 3 | Hosting | **Low budget, about $5–15 a month**: one VPS with Docker | Self-managed backups with pg_dump and WAL-G to R2 (section 2) |
| 4 | FX provider | **Frankfurter** (free, ECB) | Manual rate entry for currencies it does not cover |
| 5 | Receipts | **Yes in v1, Cloudflare R2** | Presigned uploads, new `receipts` table, Milestone 2b (+4 days) |
| 6 | Pricing | **Completely free** | No `plan` field, no Play Billing, no ads |

### Still open (small, can be decided later)
- Domain name for the API and privacy policy (e.g. `api.pennywise.app`, if it is free).
- Default category list (decided in Milestone 2).
