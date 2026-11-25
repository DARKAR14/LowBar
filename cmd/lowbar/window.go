//go:build windows

package main

import (
	"syscall"
	"unsafe"
)

func requestExit(hwnd syscall.Handle) {
	if shuttingDown {
		return
	}
	shuttingDown = true
	postMessageW.Call(uintptr(hwnd), wmClose, 0, 0)
}

func windowProc(hwnd uintptr, message uint32, wParam uintptr, lParam uintptr) uintptr {
	defer recoverPanic("window procedure")
	switch message {
	case wmTray:
		event := uint32(lParam & 0xFFFF)
		if event == wmRButtonUp || event == wmLButtonDbl {
			if globalConfig != nil && !shuttingDown && !menuPosted {
				menuPosted = true
				postMessageW.Call(hwnd, wmShowMenu, 0, 0)
			}
			return 0
		}
		return 0
	case wmShowMenu:
		menuPosted = false
		if globalConfig != nil && !shuttingDown {
			showTrayMenu(syscall.Handle(hwnd), globalConfig)
		}
		return 0
	case wmCommand:
		return 0
	case wmPowerBroadcast:
		if wParam == pbtApmResumeSuspend || wParam == pbtApmResumeAutomatic {
			scheduleTaskbarReapply(hwnd, "resume")
		} else if wParam == pbtPowerSettingChange && lParam != 0 {
			setting := (*powerBroadcastSetting)(unsafe.Pointer(lParam))
			if setting.DataLength >= 4 {
				value := *(*uint32)(unsafe.Pointer(lParam + unsafe.Offsetof(setting.Data)))
				switch setting.PowerSetting {
				case lidSwitchStateGUID:
					logEvent("INFO", "taskbar.power", "lid state changed")
					if value == 1 {
						scheduleTaskbarReapply(hwnd, "lid opened")
					}
				case sessionDisplayStatusGUID:
					logEvent("INFO", "taskbar.power", "session display state changed")
					if value == 1 {
						scheduleTaskbarReapply(hwnd, "display powered on")
					}
				}
			}
		}
		return 1 // TRUE permits Windows to continue power processing.
	case wmDisplayChange:
		scheduleTaskbarReapply(hwnd, "display change")
		return 0
	case wmTimer:
		if wParam == resumeTimerID {
			killTimer.Call(hwnd, resumeTimerID)
			if globalConfig != nil && !shuttingDown {
				logEvent("INFO", "taskbar.reapply", "retrying style after power/display transition")
				reapplyStyleSilently(globalConfig.style)
				if resumeTimerStage == 1 {
					resumeTimerStage = 2
					setTimer.Call(hwnd, resumeTimerID, 6000, 0)
				} else {
					resumeTimerStage = 0
				}
			}
			return 0
		}
	case wmBeginUpdate:
		if !shuttingDown {
			shuttingDown = true
			postMessageW.Call(hwnd, wmClose, 0, 0)
		}
		return 0
	case wmUpdateResult:
		if message := takePendingUpdateMessage(); message != "" && !shuttingDown {
			showInfo(syscall.Handle(hwnd), "LowBar Updates", message)
		}
		return 0
	case wmClose:
		killTimer.Call(hwnd, resumeTimerID)
		destroyWindow.Call(hwnd)
		return 0
	case wmDestroy:
		postQuitMessage.Call(0)
		return 0
	}
	if hookBlockMsg != 0 && message == hookBlockMsg {
		if globalConfig != nil && !shuttingDown && globalConfig.style != styleNormal {
			return 1
		}
		return 0
	}
	if taskbarMsg != 0 && message == taskbarMsg && globalConfig != nil && !shuttingDown {
		reinstallTrayIcon(syscall.Handle(hwnd))
		if !modernTaskbar {
			installExplorerHookForTaskbarCreation()
		}
		applyStyle(globalConfig.style)
		scheduleTaskbarReapply(hwnd, "taskbar recreated")
		return 0
	}
	result, _, _ := defWindowProcW.Call(hwnd, uintptr(message), wParam, lParam)
	return result
}

func scheduleTaskbarReapply(hwnd uintptr, reason string) {
	if globalConfig == nil || shuttingDown || globalConfig.style == styleNormal {
		return
	}
	// Explorer may recreate XAML surfaces after the broadcast. Two short,
	// one-shot attempts cover both immediate and delayed monitor transitions.
	killTimer.Call(hwnd, resumeTimerID)
	if modernTaskbar {
		releaseTAP()
	}
	resumeTimerStage = 1
	if ret, _, err := setTimer.Call(hwnd, resumeTimerID, 1500, 0); ret == 0 {
		resumeTimerStage = 0
		logWin32Error("taskbar.reapply", "SetTimer", err)
		return
	}
	logEvent("INFO", "taskbar.reapply", "scheduled after "+reason)
}
