package config

import (
	"os"
	"github.com/joho/godotenv"
)

type Config struct {
	AppPort string
	DBHost     string
	DBPort     string
	DBUser     string
	DBPassword string
	DBName     string
	DBSSLMode  string
}

var AppConfig Config
func LoadConfig() {
	_ = godotenv.Load()
	AppConfig = Config{
	AppPort: os.Getenv("APP_PORT"),
	DBHost:     os.Getenv("DB_HOST"),
	DBPort:     os.Getenv("DB_PORT"),
	DBUser:     os.Getenv("DB_USER"),
	DBPassword: os.Getenv("DB_PASSWORD"),
	DBName:     os.Getenv("DB_NAME"),
	DBSSLMode:  os.Getenv("DB_SSLMODE"),
	}
}