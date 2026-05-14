package routes

import (
	"io/fs"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"healthchecker-api/internal/handlers"
	"healthchecker-api/ui"
)

func RegisterRoutes(router *gin.Engine) {
	// API routes
	api := router.Group("/api")
	{
		api.GET("/health", handlers.HealthCheck)
		api.GET("/db-check", handlers.DBCheck)
	}

	// Serve embedded React UI.
	// Any request not matched by an API route is handled here.
	// Unknown paths fall back to index.html to support client-side routing.
	distFS, err := fs.Sub(ui.StaticFiles, "dist")
	if err != nil {
		panic("failed to create sub-FS for embedded UI: " + err.Error())
	}
	fileServer := http.FileServer(http.FS(distFS))

	router.NoRoute(func(c *gin.Context) {
		// Try to open the requested file; fall back to index.html for SPA routing.
		reqPath := strings.TrimPrefix(c.Request.URL.Path, "/")
		if reqPath == "" {
			reqPath = "index.html"
		}
		if f, err := distFS.Open(reqPath); err == nil {
			f.Close()
			fileServer.ServeHTTP(c.Writer, c.Request)
			return
		}
		// Serve index.html for unrecognised paths (SPA client-side routing).
		c.Request.URL.Path = "/"
		fileServer.ServeHTTP(c.Writer, c.Request)
	})
}