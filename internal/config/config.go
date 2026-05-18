package config

import (
	"log"
	"os"

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
}

var AppConfig Config

func LoadConfig() {
	err := godotenv.Load("config/app.env")
	if err != nil {
		log.Println(
			"config/app.env not found, using system environment variables",
		)
	}

	AppConfig = Config{
		AppPort:    Getenv("APP_PORT", "8080"),
		DBHost:     Getenv("DB_HOST", "localhost"),
		DBPort:     Getenv("DB_PORT", "5432"),
		DBUser:     Getenv("DB_USER", "default_user"),
		DBPassword: Getenv("DB_PASSWORD", ""),
		DBName:     Getenv("DB_NAME", "default_db"),
		DBSSLMode:  Getenv("DB_SSLMODE", "disable"),
	}
}

func Getenv(key string, fallback string) string {
	value := os.Getenv(key)
	if value == "" {
		return fallback
	}
	return value
}
