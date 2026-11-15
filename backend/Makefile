SHELL := /bin/bash
GO    ?= go
BIN   := bin
SQLC  ?= docker run --rm -u $$(id -u):$$(id -g) -v $(CURDIR):/src -w /src sqlc/sqlc:1.31.1
# The race detector needs cgo (a C compiler). Use it only when cgo is available.
RACE  := $(if $(filter 1,$(shell $(GO) env CGO_ENABLED)),-race,)

# Load .env from the repo root if it exists (for DATABASE_URL, REDIS_URL, ...).
ifneq (,$(wildcard ../.env))
include ../.env
export
endif

.PHONY: help run-api run-worker migrate migrate-down migrate-status sqlc sqlc-check test lint build

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  %-16s %s\n",$$1,$$2}'

run-api: ## Run the API locally
	$(GO) run ./cmd/api

run-worker: ## Run the background worker locally
	$(GO) run ./cmd/worker

migrate: ## Apply all pending migrations
	$(GO) run ./cmd/migrate up

migrate-down: ## Roll back the last migration
	$(GO) run ./cmd/migrate down

migrate-status: ## Show migration status
	$(GO) run ./cmd/migrate status

sqlc: ## Regenerate type-safe query code from queries/*.sql (uses Docker)
	$(SQLC) generate

sqlc-check: ## Fail if generated query code is out of date
	$(SQLC) diff

test: ## Run all tests (with the race detector when cgo is available)
	$(GO) test $(RACE) -count=1 ./...

lint: ## Run go vet and check formatting
	$(GO) vet ./...
	@test -z "$$(gofmt -l .)" || (echo "gofmt needed:"; gofmt -l .; exit 1)

build: ## Build all binaries into ./bin
	CGO_ENABLED=0 $(GO) build -trimpath -ldflags="-s -w" -o $(BIN)/ ./cmd/...
