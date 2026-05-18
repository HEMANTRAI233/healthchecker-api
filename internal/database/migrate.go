package database

import (
	"fmt"
	"healthchecker-api/internal/config"

	"github.com/golang-migrate/migrate/v4"
	"github.com/golang-migrate/migrate/v4/source/iofs"
)

func RunMigrations() error {
	connectionString := fmt.Sprintf(
		"postgres://%s:%s@%s:%s/%s?sslmode=%s",
		config.AppConfig.DBUser,
		config.AppConfig.DBPassword,
		config.AppConfig.DBHost,
		config.AppConfig.DBPort,
		config.AppConfig.DBName,
		config.AppConfig.DBSSLMode,
	)

	migrationsFS, err := iofs.New(
		MigrationFiles,
		"migrations",
	)

	if err != nil {

		return err
	}

	m, err := migrate.NewWithSourceInstance(
		"iofs",
		migrationsFS,
		connectionString,
	)

	if err != nil {

		return err
	}

	err = m.Up()

	if err != nil &&
		err != migrate.ErrNoChange {

		return err
	}

	return nil
}
