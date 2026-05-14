package main

import (
	"fmt"
	"log"
	"healthchecker-api/internal/config"
	"healthchecker-api/internal/database"
	"healthchecker-api/internal/routes"
	"github.com/gin-gonic/gin"
)

func main() {
	config.LoadConfig()
	err := database.ConnectPostgres()
	if err != nil {
	log.Fatal(err)
	}
	fmt.Println("PostgreSQL Connected")
	router := gin.Default()
	routes.RegisterRoutes(router)
	fmt.Println("Server Running On Port:", config.AppConfig.AppPort)
	router.Run(":" + config.AppConfig.AppPort)
}