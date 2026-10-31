#Requires AutoHotkey v2.0
#SingleInstance Force
#UseHook
#MaxThreadsPerHotkey 1
DllCall("SetProcessDpiAwarenessContext", "ptr", -4, "ptr")
CoordMode "Pixel", "Screen"
CoordMode "Mouse", "Screen"

global Config := {
	walkKey: "w",
	indicatorX: 842,
	indicatorY: 155,
	greenColor: 0xFFCB00,
	redColor: 0xFF3728,
	colorVariation: 20,
	boxSize: 10,         ; half-width of the scan box around the indicator point
	pollMs: 60,
	running: false,
	walking: false,
	status: "Stopped"
}

; ---------- GUI ----------
MainGui := Gui("+AlwaysOnTop", "Freeze / Scarecrow Macro")
MainGui.SetFont("s10", "Segoe UI")
MainGui.AddText("w300", "Scan point: " Config.indicatorX ", " Config.indicatorY)
MainGui.AddText("w300", "Hotkeys: F6 = Start   |   F7 = Stop")
global StatusText := MainGui.AddText("w300", "Status: Stopped")
MainGui.Show()

F6::StartMacro()
F7::StopMacro()

StartMacro() {
	global Config
	if Config.running
		return
	Config.running := true
	SetStatus("Running...")
	SetTimer(WatchLoop, Config.pollMs)
}

StopMacro() {
	global Config
	Config.running := false
	SetTimer(WatchLoop, 0)
	ReleaseWalk()
	SetStatus("Stopped")
}

WatchLoop() {
	global Config
	if !Config.running
		return

	left := Config.indicatorX - Config.boxSize
	top := Config.indicatorY - Config.boxSize
	right := Config.indicatorX + Config.boxSize
	bottom := Config.indicatorY + Config.boxSize

	isGreen := FindColor(left, top, right, bottom, Config.greenColor, Config.colorVariation)
	isRed := FindColor(left, top, right, bottom, Config.redColor, Config.colorVariation)

	if (isGreen && !isRed) {
		HoldWalk()
	} else if (isRed && !isGreen) {
		ReleaseWalk()
	}
	; if neither/both matched (mid-transition), leave current state as-is
}

FindColor(left, top, right, bottom, color, variation) {
	try {
		PixelSearch(&fx, &fy, left, top, right, bottom, color, variation)
		return true
	} catch {
		return false
	}
}

HoldWalk() {
	global Config
	if Config.walking
		return
	Config.walking := true
	Send("{" Config.walkKey " down}")
	SetStatus("Walking (green)")
}

ReleaseWalk() {
	global Config
	if !Config.walking {
		SetStatus("Frozen (red)")
		return
	}
	Config.walking := false
	Send("{" Config.walkKey " up}")
	SetStatus("Frozen (red)")
}

SetStatus(msg) {
	global Config, StatusText
	Config.status := msg
	try StatusText.Text := "Status: " msg
}
