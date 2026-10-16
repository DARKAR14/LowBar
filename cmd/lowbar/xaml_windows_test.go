//go:build windows && amd64

package main

import (
	"math"
	"syscall"
	"testing"
	"unsafe"
)

func TestXamlStyles(t *testing.T) {
	var method int
	var brush, color, border uintptr
	vtable := [10]uintptr{}
	vtable[3] = syscall.NewCallback(func(self, hwnd, b, c uintptr) uintptr {
		method, brush, color = 3, b, c
		return 0
	})
	vtable[4] = syscall.NewCallback(func(self, hwnd, c, radius uintptr) uintptr {
		method, color, brush = 4, c, radius
		return 0
	})
	vtable[5] = syscall.NewCallback(func(self, hwnd uintptr) uintptr { method = 5; return 0 })
	vtable[6] = syscall.NewCallback(func(self, hwnd, visible uintptr) uintptr { border = visible; return 0 })
	object := uintptr(unsafe.Pointer(&vtable[0]))
	old := tapService
	tapService = uintptr(unsafe.Pointer(&object))
	defer func() { tapService = old }()
	for _, tc := range []struct {
		style, method        int
		brush, color, border uintptr
	}{
		{styleClear, 3, 1, 0, 0},
		{styleOpaque, 3, 1, 0xff111111, 0},
		{styleAcrylic, 3, 0, 0xaa000000, 0},
		{styleBlur, 4, uintptr(math.Float32bits(10)), 0x55000000, 0},
		{styleNormal, 5, 0, 0, 1},
	} {
		method, brush, color, border = 0, 0, 0, 99
		if !setXamlStyle(123, tc.style) || method != tc.method || brush != tc.brush || color != tc.color || border != tc.border {
			t.Fatalf("style %d: got method=%d brush=%x color=%x border=%d", tc.style, method, brush, color, border)
		}
	}
}

func TestXamlMissingServiceFails(t *testing.T) {
	old := tapService
	tapService = 0
	defer func() { tapService = old }()
	if setXamlStyle(123, styleClear) {
		t.Fatal("missing service reported success")
	}
}
