// Package testdb gives integration tests a migrated PostgreSQL pool and
// throwaway users. Tests skip when TEST_DATABASE_URL is not set.
package testdb

import (
	"context"
	"database/sql"
	"fmt"
	"os"
	"sync"
	"testing"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	_ "github.com/jackc/pgx/v5/stdlib" // database/sql driver for goose
	"github.com/pressly/goose/v3"

	"pennywise/backend/migrations"
)

var (
	once  sync.Once
	pool  *pgxpool.Pool
	dbErr error
)

// Pool returns a pool on the migrated test database.
func Pool(t testing.TB) *pgxpool.Pool {
	t.Helper()
	url := os.Getenv("TEST_DATABASE_URL")
	if url == "" {
		t.Skip("TEST_DATABASE_URL not set")
	}
	once.Do(func() {
		sqlDB, err := sql.Open("pgx", url)
		if err != nil {
			dbErr = err
			return
		}
		defer sqlDB.Close()
		goose.SetBaseFS(migrations.FS)
		goose.SetLogger(goose.NopLogger())
		if dbErr = goose.SetDialect("postgres"); dbErr == nil {
			dbErr = goose.Up(sqlDB, ".")
		}
		if dbErr == nil {
			pool, dbErr = pgxpool.New(context.Background(), url)
		}
	})
	if dbErr != nil {
		t.Fatal(dbErr)
	}
	return pool
}

// NewUser creates a password user with the given base currency and
// deletes it (and, by cascade, all its data) when the test ends.
func NewUser(t testing.TB, p *pgxpool.Pool, baseCurrency string) uuid.UUID {
	t.Helper()
	var id uuid.UUID
	if err := p.QueryRow(context.Background(),
		`INSERT INTO users (email, password_hash, base_currency) VALUES ($1, 'x', $2) RETURNING id`,
		fmt.Sprintf("t-%s@example.com", uuid.NewString()), baseCurrency).Scan(&id); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _, _ = p.Exec(context.Background(), `DELETE FROM users WHERE id = $1`, id) })
	return id
}
