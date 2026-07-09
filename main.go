package main

import (
	"fmt"
	"healthchecker-api/internal/auth"
	"healthchecker-api/internal/config"
	"healthchecker-api/internal/database"
	"healthchecker-api/internal/routes"
	"healthchecker-api/web"
	"io/fs"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"time"

	"github.com/gin-contrib/static"
	"github.com/gin-gonic/gin"
)

func serverAddress(port string) string {
	return "127.0.0.1:" + port
}

// handleRollbackSchema is invoked when the binary is called with
// --rollback-schema <version>.  It rolls the database schema back to the
// given version and exits.
//
// install.sh (Linux) and register-service.ps1 (Windows) call this on the NEW
// binary during auto-rollback to undo any migrations that ran before the crash,
// restoring the schema to the state the previous binary expects.  Passing -1
// rolls back all migrations.
func handleRollbackSchema(args []string) {
	if len(args) < 1 {
		fmt.Fprintln(os.Stderr, "usage: HealthChecker --rollback-schema <version>")
		fmt.Fprintln(os.Stderr, "  version: target schema version (integer), or -1 to roll back all migrations")
		os.Exit(1)
	}

	targetVersion, err := strconv.ParseInt(args[0], 10, 64)
	if err != nil {
		fmt.Fprintf(os.Stderr, "rollback-schema: invalid version %q: %v\n", args[0], err)
		os.Exit(1)
	}

	config.LoadEnv()
	config.LoadConfig()

	if err := database.ConnectPostgres(); err != nil {
		fmt.Fprintf(os.Stderr, "rollback-schema: database connection failed: %v\n", err)
		os.Exit(1)
	}

	if err := database.RollbackSchemaToVersion(targetVersion); err != nil {
		fmt.Fprintf(os.Stderr, "rollback-schema: %v\n", err)
		os.Exit(1)
	}

	fmt.Printf("Schema rolled back to version %d successfully.\n", targetVersion)
	os.Exit(0)
}

func main() {
	// ========================================
	// SCHEMA ROLLBACK MODE
	// ========================================
	// When invoked with --rollback-schema <version>, perform a DB schema
	// rollback and exit.  install.sh (Linux) and register-service.ps1 (Windows)
	// use this during auto-rollback to prevent schema drift after a
	// crash-after-migrations scenario.
	if len(os.Args) >= 2 && os.Args[1] == "--rollback-schema" {
		handleRollbackSchema(os.Args[2:])
		return
	}

	// ========================================
	// LOG FILE SETUP
	// ========================================

	appDataDir, err := os.UserConfigDir()

	if err != nil {
		appDataDir, err = os.UserHomeDir()

		if err != nil {
			panic(err)
		}
	}

	logsDir := filepath.Join(
		appDataDir,
		"HealthChecker",
	)

	err = os.MkdirAll(
		logsDir,
		0755,
	)

	if err != nil {
		panic(err)
	}

	logPath := filepath.Join(
		logsDir,
		"healthchecker.log",
	)

	logFile, err := os.OpenFile(
		logPath,
		os.O_CREATE|os.O_WRONLY|os.O_APPEND,
		0666,
	)

	if err != nil {
		panic(err)
	}

	log.SetOutput(logFile)

	log.Println("APPLICATION STARTING")

	// ========================================
	// LOAD ENV
	// ========================================

	config.LoadEnv()

	log.Println("ENV LOADED")

	// ========================================
	// LOAD CONFIG
	// ========================================

	config.LoadConfig()

	log.Println("CONFIG LOADED")

	// ========================================
	// CONNECT POSTGRES
	// ========================================

	err = database.ConnectPostgres()

	if err != nil {
		log.Fatal(err)
	}

	log.Println("POSTGRES CONNECTED")

	fmt.Println("PostgreSQL Connected")

	// ========================================
	// RUN MIGRATIONS
	// ========================================

	err = database.RunMigrations()

	if err != nil {
		log.Fatal(err)
	}

	log.Println("MIGRATIONS APPLIED")

	// ========================================
	// SEED SUPERADMIN USER
	// ========================================

	auth.SeedSuperAdmin()

	log.Println("AUTH SEED COMPLETE")

	// ========================================
	// CREATE GIN ROUTER
	// ========================================

	router := gin.Default()

	routes.RegisterRoutes(router)

	// ========================================
	// EMBEDDED UI
	// ========================================

	distFS, err := fs.Sub(
		web.EmbeddedFiles,
		"dist",
	)

	if err != nil {
		log.Fatal(err)
	}

	staticDistFS, err := static.EmbedFolder(
		web.EmbeddedFiles,
		"dist",
	)

	if err != nil {
		log.Fatal(err)
	}

	router.Use(
		static.Serve(
			"/",
			staticDistFS,
		),
	)

	// ========================================
	// REACT SPA FALLBACK
	// ========================================

	router.NoRoute(func(c *gin.Context) {

		indexFile, err := distFS.Open("index.html")

		if err != nil {

			c.Status(http.StatusNotFound)
			return
		}

		defer indexFile.Close()

		stat, err := indexFile.Stat()

		if err != nil {

			c.Status(http.StatusInternalServerError)
			return
		}

		c.DataFromReader(
			http.StatusOK,
			stat.Size(),
			"text/html",
			indexFile,
			nil,
		)
	})

	// ========================================
	// SERVER START LOG
	// ========================================

	log.Println(
		"SERVER STARTING ON PORT: " +
			config.AppConfig.AppPort,
	)

	listenAddress := serverAddress(
		config.AppConfig.AppPort,
	)

	fmt.Println(
		"Server Running On:",
		listenAddress,
	)

	// ========================================
	// AUTO OPEN BROWSER
	// ========================================

	go func() {

		time.Sleep(2 * time.Second)

		url := "http://localhost/Healthchecker"

		err := exec.Command(
			"cmd",
			"/c",
			"start",
			url,
		).Start()

		if err != nil {

			log.Println(err)
		}

		log.Println("BROWSER OPEN TRIGGERED")
	}()

	// ========================================
	// START SERVER
	// ========================================

	err = router.Run(
		listenAddress,
	)

	if err != nil {

		log.Fatal(err)
	}
}
