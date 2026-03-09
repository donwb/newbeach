package api

import "embed"

// MigrationsFS holds the embedded SQL migration files.
//
//go:embed migrations/*
var MigrationsFS embed.FS
