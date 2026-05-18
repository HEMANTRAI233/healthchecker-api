package config

import (
	"github.com/joho/godotenv"
)

func loadEnvFile(path string) error {
	return godotenv.Load(path)
}
