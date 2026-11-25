//go:build windows

package main

import (
	"os"
	"syscall"
)

var (
	globalConfig         *config
	trayData             *notifyIconData
	trayIcon             syscall.Handle
	customTrayIcon       bool
	taskbarMsg           uint32
	hookBlockMsg         uint32
	processMutex         syscall.Handle
	processStyle         = styleNormal
	styleApplied         bool
	logHandle            *os.File
	shuttingDown         bool
	menuPosted           bool
	resumeTimerStage     uint8
	explorerPID          uint32
	explorerModule       uintptr
	mainHwnd             syscall.Handle
	pendingUpdateMessage string
)
