package auth

import (
	"context"
	"log"

	"healthchecker-api/internal/database"
)

// SuperAdminPasswordHash is the bcrypt hash of the superadmin's initial password.
//
// To change the default password, generate a new bcrypt hash with cost 10 and
// replace the value below before building the binary:
//
//	go run -v golang.org/x/crypto/bcrypt/...   (or any bcrypt tool)
//
// The hash below corresponds to the password: Admin@123
// Replace it with your own hash before deploying to production.
const SuperAdminPasswordHash = "$2a$10$5bcr1kyyuZ4tYB2GKeC/iexl.Mrj0wHmOy5aK78WID0YdXbCvXxVm"

// SeedSuperAdmin checks whether a superadmin user already exists in
// application_users; if not, it creates one using the hardcoded bcrypt hash.
// This runs once at startup, after migrations have been applied.
func SeedSuperAdmin() {
	ctx := context.Background()

	var count int
	err := database.DB.QueryRow(
		ctx,
		"SELECT COUNT(*) FROM application_users WHERE username = $1",
		"superadmin",
	).Scan(&count)

	if err != nil {
		log.Printf("auth seed: error checking for superadmin user: %v", err)
		return
	}

	if count > 0 {
		log.Println("auth seed: superadmin user already exists, skipping seed")
		return
	}

	_, err = database.DB.Exec(
		ctx,
		"INSERT INTO application_users (username, password_hash) VALUES ($1, $2)",
		"superadmin",
		SuperAdminPasswordHash,
	)

	if err != nil {
		log.Printf("auth seed: error creating superadmin user: %v", err)
		return
	}

	log.Println("auth seed: superadmin user created successfully")
}
