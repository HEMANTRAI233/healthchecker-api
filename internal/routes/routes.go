package routes

import (
	"github.com/gin-gonic/gin"
	"healthchecker-api/internal/auth"
	"healthchecker-api/internal/handlers"
)

func RegisterRoutes(router *gin.Engine) {
	// Public routes
	router.POST("/api/auth/login", auth.Login)

	// Protected routes – require a valid JWT
	protected := router.Group("/api")
	protected.Use(auth.RequireAuth)
	{
		protected.GET("/health", handlers.HealthCheck)
	}
}