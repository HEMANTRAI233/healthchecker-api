package config

import (
	"log"
	"os"
	"path/filepath"
)

type Config struct {
	AppPort    string
	DBHost     string
	DBPort     string
	DBUser     string
	DBPassword string
	DBName     string
	DBSSLMode  string
}

var AppConfig Config

// ========================================
// LOAD ENV FILE
// ========================================

func LoadEnv() {

	exePath, err := os.Executable()

	if err != nil {

		log.Fatal(err)
	}

	exeDir := filepath.Dir(exePath)

	envPath := filepath.Join(
		exeDir,
		"config",
		"app.env",
	)

	_, err = os.Stat(envPath)

	if err != nil {

		log.Println(
			"config/app.env not found, using system environment variables",
		)

		return
	}

	err = loadEnvFile(envPath)

	if err != nil {

		log.Fatal(err)
	}
}

// ========================================
// LOAD CONFIG INTO STRUCT
// ========================================

func LoadConfig() {

	AppConfig = Config{

		AppPort: GetEnv(
			"APP_PORT",
			"8080",
		),

		DBHost: GetEnv(
			"DB_HOST",
			"localhost",
		),

		DBPort: GetEnv(
			"DB_PORT",
			"5432",
		),

		DBUser: GetEnv(
			"DB_USER",
			"postgres",
		),

		DBPassword: GetEnv(
			"DB_PASSWORD",
			"",
		),

		DBName: GetEnv(
			"DB_NAME",
			"healthchecker",
		),

		DBSSLMode: GetEnv(
			"DB_SSLMODE",
			"disable",
		),
	}
}

// ========================================
// GET ENV VALUE WITH FALLBACK
// ========================================

func GetEnv(
	key string,
	fallback string,
) string {

	value := os.Getenv(key)

	if value == "" {

		return fallback
	}

	return value
}
