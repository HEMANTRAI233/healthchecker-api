package main

import (
	"context"
	"embed"
	"os/signal"
	"syscall"

	"healthchecker-api/internal/app"
)

//go:embed migrations/*.sql
var migrationFiles embed.FS

func runInteractive() error {
	ctx, cancel := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer cancel()
	return app.Run(ctx, migrationFiles)
}
