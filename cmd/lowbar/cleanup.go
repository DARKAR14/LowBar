//go:build windows

package main

func cleanup() {
	defer recoverPanic("cleanup")
	restoreTaskbar()
	closeTAP()
	if processMutex != 0 {
		closeHandle.Call(uintptr(processMutex))
		processMutex = 0
	}
	if trayData != nil {
		removeTrayIcon(trayData)
		trayData = nil
	}
	destroyTrayIconHandle()
	closeLog()
}
