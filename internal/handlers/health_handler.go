package handlers

import (
	"context"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"healthchecker-api/internal/database"
)

// HealthCheck returns a simple liveness response.
func HealthCheck(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{
		"status": "UP",
	})
}

type DBCheckResponse struct {
	Status    string    `json:"status"`
	DBVersion string    `json:"db_version"`
	Timestamp time.Time `json:"timestamp"`
}

// DBCheck queries PostgreSQL for its version and current timestamp.
func DBCheck(c *gin.Context) {
	var version string
	var timestamp time.Time

	err := database.DB.QueryRow(
		context.Background(),
		"SELECT version(), now()",
	).Scan(&version, &timestamp)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"status": "DOWN",
			"error":  err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, DBCheckResponse{
		Status:    "UP",
		DBVersion: version,
		Timestamp: timestamp,
	})
}