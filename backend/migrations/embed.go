// Package migrations embeds the SQL migration files into the binary.
package migrations

import "embed"

// FS holds every *.sql migration, applied in order by goose.
//
//go:embed *.sql
var FS embed.FS
