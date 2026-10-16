//go:build windows && xamlpreview

package main

// Releases of this fork are installed through install.ps1. Excluding the
// updater from the preview build also excludes its HTTP, ZIP and crypto
// dependencies from the resident process.
func runUpdateHelper([]string) int     { return 1 }
func scheduleUpdateChecks(*config)     {}
func startUpdateCheckManually()        {}
func checkForUpdates(bool)             {}
func takePendingUpdateMessage() string { return "" }
