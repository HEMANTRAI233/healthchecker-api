package web

import "embed"

//go:embed dist/*
var EmbeddedFiles embed.FS
