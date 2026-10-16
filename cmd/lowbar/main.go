//go:build windows

package main

import (
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"runtime/debug"
	"unsafe"
)

func main() {
	if len(os.Args) > 1 && os.Args[1] == "--apply-update" {
		os.Exit(runUpdateHelper(os.Args[1:]))
	}
	if len(os.Args) > 1 && os.Args[1] == "--shutdown" {
		requestExistingInstanceExit()
		return
	}

	runtime.LockOSThread()
	defer runtime.UnlockOSThread()
	modernTaskbar = detectModernTaskbar()
	openLog()
	logContext()
	defer func() {
		if v := recover(); v != nil {
			logEvent("FATAL", "main", fmt.Sprintf("panic=%v | stack=\n%s", v, debug.Stack()))
		}
		cleanup()
	}()
	prepareProcess()
	processMutex = ensureSingleInstance()
	if processMutex == 0 {
		return
	}
	cfg := loadConfig()
	// Earlier XAML releases forcibly disabled updates and persisted that value.
	// Enable them once on migration; later menu choices remain respected.
	if previewBuild {
		marker := filepath.Join(appDataDir(), "updates-v2-migrated")
		if _, err := os.Stat(marker); os.IsNotExist(err) {
			cfg.autoUpdate = true
			_ = os.MkdirAll(appDataDir(), 0700)
			_ = os.WriteFile(marker, []byte("1"), 0600)
		}
	}
	startup := isStartupEnabled()
	if cfg.startup != startup {
		cfg.startup = startup
		_ = saveConfig(cfg)
	}
	globalConfig = &cfg
	taskbarRaw, _, _ := registerWindowMessageW.Call(uintptr(unsafe.Pointer(utf16ptr(taskbarMessage))))
	taskbarMsg = uint32(taskbarRaw)
	hookRaw, _, _ := registerWindowMessageW.Call(uintptr(unsafe.Pointer(utf16ptr("LowBar.ShouldBlockTaskbarComposition"))))
	hookBlockMsg = uint32(hookRaw)
	if err := loadTrayIcon(); err != nil {
		showError(appName, err)
		return
	}
	hwnd, err := createHiddenWindow()
	if err != nil {
		showError(appName, err)
		return
	}
	mainHwnd = hwnd
	defer destroyWindow.Call(uintptr(hwnd))
	tray, err := installTrayIcon(hwnd)
	if err != nil {
		showError(appName, err)
		return
	}
	trayData = &tray
	applyStyle(cfg.style)
	if !modernTaskbar {
		startExplorerIntegration(hwnd)
	}
	if err := saveConfig(cfg); err != nil {
		logError("config.save", "initial config save failed", err)
	}
	scheduleUpdateChecks(&cfg)
	_ = messageLoop()
}
