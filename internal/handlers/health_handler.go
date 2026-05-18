package handlers

import (
	"context"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"healthchecker-api/internal/database"
)

type DBCheckResponse struct {
	Status          string    `json:"status"`
	PostgresVersion string    `json:"postgres_version"`
	CurrentTime     time.Time `json:"current_time"`
}

func dbCheck(c *gin.Context) {
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
		Status:          "UP",
		PostgresVersion: version,
		CurrentTime:     timestamp,
	})
}

// HealthCheck queries PostgreSQL and returns service + database health.
func HealthCheck(c *gin.Context) {
	dbCheck(c)
}

// DBCheck exists for compatibility and delegates to the same health payload.
func DBCheck(c *gin.Context) {
	dbCheck(c)
}
