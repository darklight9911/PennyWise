// Command migrate applies database migrations.
//
// Usage: migrate [up|down|down-to N|status|redo|version]   (default: up)
package main

import (
	"context"
	"database/sql"
	"fmt"
	"log/slog"
	"os"

	_ "github.com/jackc/pgx/v5/stdlib"
	"github.com/pressly/goose/v3"

	"pennywise/backend/migrations"
)

func main() {
	if err := run(); err != nil {
		slog.Error("migrate failed", "err", err)
		os.Exit(1)
	}
}

func run() error {
	url := os.Getenv("DATABASE_URL")
	if url == "" {
		return fmt.Errorf("DATABASE_URL is required")
	}
	cmd, args := "up", []string(nil)
	if len(os.Args) > 1 {
		cmd, args = os.Args[1], os.Args[2:] // e.g. "down-to 0"
	}

	db, err := sql.Open("pgx", url)
	if err != nil {
		return err
	}
	defer db.Close()

	goose.SetBaseFS(migrations.FS)
	if err := goose.SetDialect("postgres"); err != nil {
		return err
	}
	return goose.RunContext(context.Background(), cmd, db, ".", args...)
}
