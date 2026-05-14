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

	"github.com/gin-contrib/static"
	"github.com/gin-gonic/gin"
)

func main() {
	config.LoadConfig()
	err := database.ConnectPostgres()
	if err != nil {
		log.Fatal(err)
	}
	
	fmt.Println("PostgreSQL Connected")
	err = database.RunMigrations()
	if err != nil {
		log.Fatal(err)
	}

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
		stat, _ := indexFile.Stat()
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
	router.Run(":" + config.AppConfig.AppPort)
}
