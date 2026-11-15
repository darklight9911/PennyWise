# pennyWise

An all-in-one personal finance app (Android + iOS) with a Go backend.
See [PLAN.md](PLAN.md) for the full product and architecture plan.

| Folder | What it is |
|---|---|
| `backend/` | Go API (`cmd/api`), background worker (`cmd/worker`), migrations (`cmd/migrate`) |
| `mobile/` | Flutter app |
| `docker-compose.yml` | Local PostgreSQL 18 + Redis 8 (and optionally the API/worker) |

## Requirements

- Go 1.27+
- Flutter (stable) with an Android SDK for device builds
- Docker with the Compose plugin

## Run the backend locally

```bash
cp .env.example .env
# put a secret in .env: JWT_SECRET=$(openssl rand -base64 48)
docker compose up -d          # Postgres + Redis
cd backend
make migrate                  # create tables
make run-api                  # http://localhost:8080/healthz
make run-worker               # in a second terminal
```

Or run everything in containers:

```bash
docker compose --profile app up -d --build
```

Useful commands (in `backend/`): `make test`, `make lint`, `make sqlc`, `make help`.

`make test` also runs the integration tests when `TEST_DATABASE_URL` and
`TEST_REDIS_URL` are set (see `.env.example`). Create the test database once:

```bash
docker compose exec postgres psql -U pennywise -c "CREATE DATABASE pennywise_test"
```

In development, emails (verification, password reset) are not sent. They are
printed to the API log, so you can copy the link from there.

## API (so far)

| Method | Path | Auth |
|---|---|---|
| POST | `/v1/auth/register` | – |
| POST | `/v1/auth/login` | – |
| POST | `/v1/auth/google` | – |
| POST | `/v1/auth/refresh` | – |
| POST | `/v1/auth/logout` | – |
| POST | `/v1/auth/verify-email` | – |
| POST | `/v1/auth/resend-verification` | Bearer |
| POST | `/v1/auth/forgot-password` | – |
| POST | `/v1/auth/reset-password` | – |
| GET | `/v1/me` | Bearer |

## Run the mobile app

```bash
cd mobile
flutter pub get
flutter run
```

## Health endpoints

| Path | Meaning |
|---|---|
| `/healthz` | Process is alive |
| `/readyz` | Postgres and Redis are reachable |
| `/metrics` | Prometheus metrics |
