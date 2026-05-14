package ui

import "embed"

// StaticFiles holds the embedded React build output.
// At build time the CI pipeline downloads the versioned frontend release artifact,
// extracts it into this directory (ui/dist/), then compiles the Go binary so the
// real UI is embedded. The placeholder index.html below is used for local builds.
//
//go:embed all:dist
var StaticFiles embed.FS
