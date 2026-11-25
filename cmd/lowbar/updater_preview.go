//go:build windows && xamlpreview

package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"sync"
	"syscall"
	"time"
)

// The network client runs in a short-lived PowerShell process, keeping the
// resident taskbar process small.
func runUpdateHelper([]string) int { return 1 }

var updateScheduleOnce sync.Once

func scheduleUpdateChecks(cfg *config) {
	if cfg == nil || !cfg.autoUpdate {
		return
	}
	updateScheduleOnce.Do(func() {
		time.AfterFunc(10*time.Second, func() {
			checkForUpdates(false)
			ticker := time.NewTicker(24 * time.Hour)
			defer ticker.Stop()
			for range ticker.C {
				checkForUpdates(false)
			}
		})
	})
}

func startUpdateCheckManually() { go checkForUpdates(true) }

func checkForUpdates(manual bool) {
	if !manual && (globalConfig == nil || !globalConfig.autoUpdate) {
		return
	}
	exe, err := os.Executable()
	if err != nil {
		logError("updater", "unable to locate LowBar", err)
		return
	}
	dir := filepath.Dir(exe)
	script := filepath.Join(dir, "update.ps1")
	if _, err := os.Stat(script); err != nil {
		logError("updater", "update.ps1 is missing", err)
		return
	}
	args := []string{"-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script, "-CurrentVersion", buildVersion, "-InstallRoot", dir}
	if manual {
		args = append(args, "-Manual")
	}
	cmd := exec.Command("powershell.exe", args...)
	cmd.Dir = dir
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
	if err := cmd.Start(); err != nil {
		logError("updater", "unable to start update check", err)
		return
	}
	go func() {
		if err := cmd.Wait(); err != nil {
			logError("updater", "update check exited with error", err)
		}
	}()
}

func takePendingUpdateMessage() string { return "" }
