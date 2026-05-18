package app

import (
	"context"
	"errors"
	"fmt"
	"io/fs"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"healthchecker-api/internal/config"
	"healthchecker-api/internal/database"
	"healthchecker-api/internal/routes"
)

func Run(ctx context.Context, migrationFS fs.FS) error {
	config.LoadConfig()
	gin.SetMode(config.AppConfig.GinMode)

	if err := database.ConnectPostgres(); err != nil {
		return fmt.Errorf("failed to connect to PostgreSQL: %w", err)
	}
	if err := database.RunMigrations(migrationFS); err != nil {
		return fmt.Errorf("failed to run migrations: %w", err)
	}

	router := gin.Default()
	if err := routes.RegisterRoutes(router); err != nil {
		return fmt.Errorf("failed to register routes: %w", err)
	}

	server := &http.Server{
		Addr:    ":" + config.AppConfig.AppPort,
		Handler: router,
	}

	errCh := make(chan error, 1)
	go func() {
		err := server.ListenAndServe()
		if err != nil && !errors.Is(err, http.ErrServerClosed) {
			errCh <- err
		}
		close(errCh)
	}()

	select {
	case <-ctx.Done():
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		return server.Shutdown(shutdownCtx)
	case err := <-errCh:
		return err
	}
}
