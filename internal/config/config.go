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
	JWTSecret  string
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

	envPaths := []string{
		filepath.Join(
			exeDir,
			"config",
			"app.env",
		),
		filepath.Join(
			exeDir,
			"internal",
			"config",
			"app.env",
		),
	}

	for _, envPath := range envPaths {

		_, err = os.Stat(envPath)

		if err != nil {
			continue
		}

		err = loadEnvFile(envPath)

		if err != nil {
			log.Fatal(err)
		}

		return
	}

	log.Println(
		"config/app.env not found, using system environment variables",
	)
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

		JWTSecret: GetEnv(
			"JWT_SECRET",
			"change-me-in-production",
		),
	}

	if AppConfig.JWTSecret == "change-me-in-production" {
		log.Println("WARNING: JWT_SECRET is set to the insecure default value. " +
			"Set the JWT_SECRET environment variable to a strong random secret before deploying to production.")
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
