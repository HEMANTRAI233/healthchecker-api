package database

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5/pgxpool"
	"healthchecker-api/internal/config"
)

var DB *pgxpool.Pool

// ConnectPostgres connects to PostgreSQL, creating the target database if it does not exist.
func ConnectPostgres() error {
	cfg := config.AppConfig

	// First connect to the default "postgres" maintenance database to bootstrap the target DB.
	maintenanceDSN := fmt.Sprintf(
		"host=%s port=%s user=%s password=%s dbname=postgres sslmode=%s",
		cfg.DBHost, cfg.DBPort, cfg.DBUser, cfg.DBPassword, cfg.DBSSLMode,
	)
	mainPool, err := pgxpool.New(context.Background(), maintenanceDSN)
	if err != nil {
		return fmt.Errorf("failed to connect to postgres maintenance db: %w", err)
	}
	defer mainPool.Close()

	// Create target database if it does not already exist.
	var exists bool
	err = mainPool.QueryRow(
		context.Background(),
		"SELECT EXISTS(SELECT 1 FROM pg_database WHERE datname = $1)",
		cfg.DBName,
	).Scan(&exists)
	if err != nil {
		return fmt.Errorf("failed to check database existence: %w", err)
	}
	if !exists {
		_, err = mainPool.Exec(
			context.Background(),
			fmt.Sprintf("CREATE DATABASE %q", cfg.DBName),
		)
		if err != nil {
			return fmt.Errorf("failed to create database %q: %w", cfg.DBName, err)
		}
		fmt.Printf("Database %q created\n", cfg.DBName)
	}

	// Connect to the target database.
	dsn := fmt.Sprintf(
		"host=%s port=%s user=%s password=%s dbname=%s sslmode=%s",
		cfg.DBHost, cfg.DBPort, cfg.DBUser, cfg.DBPassword, cfg.DBName, cfg.DBSSLMode,
	)
	pool, err := pgxpool.New(context.Background(), dsn)
	if err != nil {
		return fmt.Errorf("failed to connect to database %q: %w", cfg.DBName, err)
	}
	DB = pool
	return nil
}