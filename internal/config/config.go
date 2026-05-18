package config

import (
	"os"
	"path/filepath"

	"github.com/joho/godotenv"
)

type Config struct {
	AppPort    string
	DBHost     string
	DBPort     string
	DBUser     string
	DBPassword string
	DBName     string
	DBSSLMode  string
	GinMode    string
}

var AppConfig Config

func getEnv(key, defaultVal string) string {
	if val := os.Getenv(key); val != "" {
		return val
	}
	return defaultVal
}

func LoadConfig() {
	loadEnvFiles()
	AppConfig = Config{
		AppPort:    getEnv("APP_PORT", "8080"),
		DBHost:     getEnv("DB_HOST", "localhost"),
		DBPort:     getEnv("DB_PORT", "5432"),
		DBUser:     getEnv("DB_USER", "postgres"),
		DBPassword: getEnv("DB_PASSWORD", "postgres"),
		DBName:     getEnv("DB_NAME", "healthchecker"),
		DBSSLMode:  getEnv("DB_SSLMODE", "disable"),
		GinMode:    getEnv("GIN_MODE", "release"),
	}
}

func loadEnvFiles() {
	_ = godotenv.Load()

	exePath, err := os.Executable()
	if err != nil {
		return
	}
	exeDir := filepath.Dir(exePath)
	_ = godotenv.Overload(filepath.Join(exeDir, ".env"))
}
