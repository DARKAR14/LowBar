//go:build windows

package main

import (
	"syscall"
	"unsafe"
)

// Register for transitions that do not suspend Windows or change resolution.
var lidSwitchStateGUID = syscall.GUID{Data1: 0xba3e0f4d, Data2: 0xb817, Data3: 0x4094, Data4: [8]byte{0xa2, 0xd1, 0xd5, 0x63, 0x79, 0xe6, 0xa0, 0xf3}}
var sessionDisplayStatusGUID = syscall.GUID{Data1: 0x2b84c20e, Data2: 0xad23, Data3: 0x4ddf, Data4: [8]byte{0x93, 0xdb, 0x05, 0xff, 0xbd, 0x7e, 0xfc, 0xa5}}

type powerBroadcastSetting struct {
	PowerSetting syscall.GUID
	DataLength   uint32
	Data         byte
}

var powerNotificationHandles []uintptr

func registerTaskbarPowerNotifications(hwnd syscall.Handle) {
	for _, guid := range []*syscall.GUID{&lidSwitchStateGUID, &sessionDisplayStatusGUID} {
		handle, _, err := registerPowerSettingNotification.Call(uintptr(hwnd), uintptr(unsafe.Pointer(guid)), 0)
		if handle == 0 {
			logWin32Error("taskbar.power", "RegisterPowerSettingNotification", err)
			continue
		}
		powerNotificationHandles = append(powerNotificationHandles, handle)
	}
}

func unregisterTaskbarPowerNotifications() {
	for _, handle := range powerNotificationHandles {
		unregisterPowerSettingNotification.Call(handle)
	}
	powerNotificationHandles = nil
}
