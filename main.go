package main

import (
	"fmt"
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
	"time"

	"github.com/gin-contrib/static"
	"github.com/gin-gonic/gin"
)

func main() {

	// ========================================
	// LOG FILE SETUP
	// ========================================

	exePath, err := os.Executable()

	if err != nil {
		panic(err)
	}

	exeDir := filepath.Dir(exePath)

	logPath := filepath.Join(
		exeDir,
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

	fmt.Println(
		"Server Running On Port:",
		config.AppConfig.AppPort,
	)

	// ========================================
	// AUTO OPEN BROWSER
	// ========================================

	go func() {

		time.Sleep(2 * time.Second)

		url := "http://127.0.0.1:" +
			config.AppConfig.AppPort

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
		":" + config.AppConfig.AppPort,
	)

	if err != nil {

		log.Fatal(err)
	}
}
