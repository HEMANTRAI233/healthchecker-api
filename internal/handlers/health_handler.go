package handlers

import (
	"context"
	"healthchecker-api/internal/database"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
)

type HealthResponse struct {
	Status          string `json:"status"`
	PostgresVersion string `json:"postgres_version,omitempty"`
	CurrentTime     string `json:"current_time,omitempty"`
}

func HealthCheck(c *gin.Context) {
	var postgresVersion string
	query := "SELECT version();"
	err := database.DB.QueryRow(
		context.Background(),
		query,
	).Scan(&postgresVersion)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"status": "DOWN",
		})
		return
	}

	response := HealthResponse{
		Status:          "UP",
		PostgresVersion: postgresVersion,
		CurrentTime:     time.Now().Format("2006-01-02 15:04:05"),
	}
	c.JSON(http.StatusOK, response)
}
