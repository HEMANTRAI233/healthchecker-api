package main

import (
	"embed"
	"fmt"
	"log"

	"github.com/gin-gonic/gin"
	"healthchecker-api/internal/config"
	"healthchecker-api/internal/database"
	"healthchecker-api/internal/routes"
)

//go:embed migrations/*.sql
var migrationFiles embed.FS

func main() {
	config.LoadConfig()

	gin.SetMode(config.AppConfig.GinMode)

	// Connect to PostgreSQL (creates the DB if it does not exist).
	if err := database.ConnectPostgres(); err != nil {
		log.Fatalf("Failed to connect to PostgreSQL: %v", err)
	}
	fmt.Println("PostgreSQL connected")

	// Apply pending schema migrations.
	if err := database.RunMigrations(migrationFiles); err != nil {
		log.Fatalf("Failed to run migrations: %v", err)
	}
	fmt.Println("Migrations applied")

	router := gin.Default()
	routes.RegisterRoutes(router)

	fmt.Printf("Server running on port: %s\n", config.AppConfig.AppPort)
	if err := router.Run(":" + config.AppConfig.AppPort); err != nil {
		log.Fatalf("Server failed: %v", err)
	}
}