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
	"path/filepath"

	"github.com/gin-contrib/static"
	"github.com/gin-gonic/gin"
)

func main() {
	exepath, _ := os.Executable()
	exeDir := filepath.Dir(exepath)
	logPath := filepath.Join(exeDir, "healthchecker.log")
	LogFile, err := os.OpenFile(
		logPath,
		os.O_CREATE|os.O_WRONLY|os.O_APPEND,
		0666,
	)
	if err != nil {
		panic(err)
	}
	log.SetOutput(LogFile)
	log.Println("APPLICATION STARTING")

	config.LoadConfig()
	err = database.ConnectPostgres()
	if err != nil {
		log.Fatal(err)
	}
	log.Println("CONFIG LOADED")

	fmt.Println("PostgreSQL Connected")
	err = database.RunMigrations()
	if err != nil {
		log.Fatal(err)
	}
	log.Println("PostgreSQL Connected")
	log.Println("Migrations Applied")

	router := gin.Default()
	routes.RegisterRoutes(router)
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
	fmt.Println(
		"Server Running On Port:",
		config.AppConfig.AppPort,
	)
	err = router.Run(":" + config.AppConfig.AppPort)
	if err != nil {
		log.Fatal(err)
	}
	log.Println("Server open Triggered")
}
