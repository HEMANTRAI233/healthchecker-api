package auth

import (
	"context"
	"net/http"
	"time"

	"healthchecker-api/internal/config"
	"healthchecker-api/internal/database"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"golang.org/x/crypto/bcrypt"
)

type loginRequest struct {
	Username string `json:"username" binding:"required"`
	Password string `json:"password" binding:"required"`
}

type loginResponse struct {
	Token string `json:"token"`
}

// Login handles POST /api/auth/login.
// It looks up the user by username, verifies the password against the stored
// bcrypt hash, and returns a signed JWT on success.
// When the username is not found a dummy bcrypt comparison is performed so
// that both the "no such user" and "wrong password" code paths take roughly
// the same amount of time, preventing username enumeration via response timing.
func Login(c *gin.Context) {
	var req loginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "username and password are required"})
		return
	}

	var userID int
	var storedHash string
	err := database.DB.QueryRow(
		context.Background(),
		"SELECT id, password_hash FROM application_users WHERE username = $1",
		req.Username,
	).Scan(&userID, &storedHash)

	if err != nil {
		// Perform a dummy bcrypt comparison to make the timing indistinguishable
		// from a real password check, preventing username enumeration.
		_ = bcrypt.CompareHashAndPassword([]byte(SuperAdminPasswordHash), []byte(req.Password))
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid username or password"})
		return
	}

	if err := bcrypt.CompareHashAndPassword([]byte(storedHash), []byte(req.Password)); err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid username or password"})
		return
	}

	token, err := generateJWT(userID, req.Username)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "could not generate token"})
		return
	}

	c.JSON(http.StatusOK, loginResponse{Token: token})
}

func generateJWT(userID int, username string) (string, error) {
	claims := jwt.MapClaims{
		"sub":      userID,
		"username": username,
		"exp":      time.Now().Add(24 * time.Hour).Unix(),
		"iat":      time.Now().Unix(),
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString([]byte(config.AppConfig.JWTSecret))
}
