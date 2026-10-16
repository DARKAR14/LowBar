//go:build windows

package main

import (
	"fmt"
	"math"
	"os"
	"path/filepath"
	"runtime"
	"syscall"
	"unsafe"
)

// ExplorerTAP 2026.2, ITaskbarAppearanceService (API version 4).
// See THIRD_PARTY.md. All calls belong to the locked UI thread.
var tapIID = syscall.GUID{Data1: 0x5bcf9150, Data2: 0xc28a, Data3: 0x4ef2, Data4: [8]byte{0x91, 0x3c, 0x4c, 0x3e, 0xa2, 0xf5, 0xea, 0xd0}}
var tapService uintptr
var tapDLL *syscall.DLL // Keep loaded: COM proxy registration uses its code.
var tapPID uint32
var tapInitialized bool
var modernTaskbar bool

func detectModernTaskbar() bool {
	var version struct {
		Size, Major, Minor, Build, Platform uint32
		ServicePack                         [128]uint16
	}
	version.Size = uint32(unsafe.Sizeof(version))
	ret, _, _ := syscall.NewLazyDLL("ntdll.dll").NewProc("RtlGetVersion").Call(uintptr(unsafe.Pointer(&version)))
	return ret == 0 && version.Build >= 22621
}

func tapCall(method int, args ...uintptr) error {
	if tapService == 0 {
		return fmt.Errorf("XAML service unavailable")
	}
	vtable := *(*uintptr)(unsafe.Pointer(tapService))
	fn := *(*uintptr)(unsafe.Pointer(vtable + uintptr(method)*unsafe.Sizeof(uintptr(0))))
	ret, _, _ := syscall.SyscallN(fn, append([]uintptr{tapService}, args...)...)
	if int32(ret) < 0 {
		return fmt.Errorf("XAML method %d: HRESULT 0x%08x", method, uint32(ret))
	}
	return nil
}

func releaseTAP() {
	if tapService != 0 {
		_ = tapCall(2)
		tapService = 0
	}
	tapPID = 0
}

func ensureTAP() error {
	pid, hwnd := currentTaskbarOwner()
	if pid == 0 {
		return fmt.Errorf("taskbar not available")
	}
	if tapService != 0 && tapPID == pid {
		return nil
	}
	releaseTAP()
	if runtime.GOARCH != "amd64" {
		return fmt.Errorf("this preview requires Windows x64")
	}
	if !tapInitialized {
		ret, _, _ := syscall.NewLazyDLL("combase.dll").NewProc("RoInitialize").Call(0)
		if int32(ret) < 0 {
			return fmt.Errorf("RoInitialize: HRESULT 0x%08x", uint32(ret))
		}
		tapInitialized = true
	}
	if tapDLL == nil {
		exe, err := os.Executable()
		if err != nil {
			return err
		}
		tapDLL, err = syscall.LoadDLL(filepath.Join(filepath.Dir(exe), "ExplorerTAP.dll"))
		if err != nil {
			return fmt.Errorf("load ExplorerTAP.dll: %w", err)
		}
	}
	inject, err := tapDLL.FindProc("InjectExplorerTAP")
	if err != nil {
		return err
	}
	ret, _, _ := inject.Call(uintptr(hwnd), uintptr(unsafe.Pointer(&tapIID)), uintptr(unsafe.Pointer(&tapService)))
	if int32(ret) < 0 {
		tapService = 0
		return fmt.Errorf("InjectExplorerTAP: HRESULT 0x%08x", uint32(ret))
	}
	if tapService == 0 {
		return fmt.Errorf("InjectExplorerTAP returned no service")
	}
	if err := tapCall(8, uintptr(os.Getpid())); err != nil {
		releaseTAP()
		return fmt.Errorf("register automatic restore (close other taskbar customizers): %w", err)
	}
	tapPID = pid
	logEvent("INFO", "taskbar.xaml", fmt.Sprintf("connected to Explorer pid=%d; event-driven XAML backend", pid))
	return nil
}

func setXamlStyle(hwnd syscall.Handle, style int) bool {
	var err error
	switch style {
	case styleNormal:
		err = tapCall(5, uintptr(hwnd))
	case styleClear:
		err = tapCall(3, uintptr(hwnd), 1, 0)
	case styleOpaque:
		err = tapCall(3, uintptr(hwnd), 1, 0xff111111)
	case styleBlur:
		err = tapCall(4, uintptr(hwnd), 0x55000000, uintptr(math.Float32bits(10)))
	case styleAcrylic:
		err = tapCall(3, uintptr(hwnd), 0, 0xaa000000)
	}
	if err == nil {
		visible := uintptr(0)
		if style == styleNormal {
			visible = 1
		}
		err = tapCall(6, uintptr(hwnd), visible)
	}
	if err != nil {
		logError("taskbar.xaml", "apply style", err)
		return false
	}
	return true
}

func closeTAP() {
	if tapService != 0 {
		_ = tapCall(7)
	}
	releaseTAP()
	if tapInitialized {
		syscall.NewLazyDLL("combase.dll").NewProc("RoUninitialize").Call()
		tapInitialized = false
	}
}
