package auth

import (
	"context"
	"log"
	"os"

	"healthchecker-api/internal/database"
)

// SuperAdminPasswordHash is the bcrypt hash of the superadmin's initial password.
//
// To change the default password, generate a new bcrypt hash with cost ≥ 10:
//
//	go run golang.org/x/crypto/bcrypt/...   (or any bcrypt tool)
//
// The hash below corresponds to the password: Admin@123
// Replace this constant with your own hash before building for production.
// You can also override it at runtime by setting the SUPERADMIN_PASSWORD_HASH
// environment variable, which takes priority over this compile-time constant.
const SuperAdminPasswordHash = "$2a$10$5bcr1kyyuZ4tYB2GKeC/iexl.Mrj0wHmOy5aK78WID0YdXbCvXxVm"

// SeedSuperAdmin checks whether a superadmin user already exists in
// application_users; if not, it creates one using the bcrypt hash.
// The hash is taken from the SUPERADMIN_PASSWORD_HASH environment variable
// when set; otherwise the compile-time constant SuperAdminPasswordHash is used.
// This runs once at startup, after migrations have been applied.
func SeedSuperAdmin() {
	passwordHash := os.Getenv("SUPERADMIN_PASSWORD_HASH")
	if passwordHash == "" {
		passwordHash = SuperAdminPasswordHash
	}
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
		passwordHash,
	)

	if err != nil {
		log.Printf("auth seed: error creating superadmin user: %v", err)
		return
	}

	log.Println("auth seed: superadmin user created successfully")
}
