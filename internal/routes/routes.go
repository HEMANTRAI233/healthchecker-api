package routes

import (
	"github.com/gin-gonic/gin"
	"healthchecker-api/internal/handlers"
)

func RegisterRoutes(router *gin.Engine) {
	router.GET("/api/health", handlers.HealthCheck)
}