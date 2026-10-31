#Requires AutoHotkey v2.0
#SingleInstance Force
#UseHook
#MaxThreadsPerHotkey 1
DllCall("SetProcessDpiAwarenessContext", "ptr", -4, "ptr")
CoordMode "Pixel", "Screen"
CoordMode "Mouse", "Screen"

global Config := {
	walkKey: "w",
	greenColor: "",       ; set via calibration
	redColor: "",         ; set via calibration
	colorVariation: 20,
	indicatorX: 0,
	indicatorY: 0,
	boxSize: 14,           ; half-width of the scan box around the indicator point
	pollMs: 60,
	running: false,
	walking: false,
	status: "Stopped"
}

global SettingsFile := A_ScriptDir "\freeze-macro-settings.ini"
LoadSettings()

; ---------- GUI ----------
MainGui := Gui("+AlwaysOnTop", "Freeze / Scarecrow Macro")
MainGui.SetFont("s10", "Segoe UI")

MainGui.AddText("w320", "1. Hover your mouse over the status circle (the red/green dot next to `"Freeze!`"/`"Walk to the Scarecrow!`") then press F8 while it's GREEN.")
MainGui.AddText("w320", "2. Do the same while it's RED (press F8 again).")
global CalibText := MainGui.AddText("w320 vCalibText cGray", GetCalibText())

MainGui.AddText("w320 y+10", "Hotkeys: F6 = Start, F7 = Stop, F8 = Calibrate (alternates green/red)")
StatusText := MainGui.AddText("w320 vStatusText", "Status: Stopped")
MainGui.Show()

F6::StartMacro()
F7::StopMacro()
F8::Calibrate()

GetCalibText() {
	global Config
	g := Config.greenColor = "" ? "not set" : Config.greenColor
	r := Config.redColor = "" ? "not set" : Config.redColor
	return "Green: " g "   |   Red: " r "   |   Point: " Config.indicatorX "," Config.indicatorY
}

Calibrate() {
	global Config, CalibText
	MouseGetPos(&mx, &my)
	c := PixelGetColor(mx, my, "RGB")

	if (Config.greenColor = "") {
		Config.greenColor := c
		Config.indicatorX := mx
		Config.indicatorY := my
		SetStatus("Calibrated GREEN at " mx "," my ". Now hover + F8 on RED.")
	} else if (Config.redColor = "") {
		Config.redColor := c
		SetStatus("Calibrated RED. Ready — press F6 to start.")
		SaveSettings()
	} else {
		; re-calibrate from scratch
		Config.greenColor := c
		Config.redColor := ""
		Config.indicatorX := mx
		Config.indicatorY := my
		SetStatus("Re-calibrating. GREEN set, now hover + F8 on RED.")
	}

	CalibText.Text := GetCalibText()
}

StartMacro() {
	global Config
	if (Config.greenColor = "" || Config.redColor = "") {
		SetStatus("Calibrate first (F8 on green, then F8 on red).")
		return
	}
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

SaveSettings() {
	global Config, SettingsFile
	IniWrite(Config.greenColor, SettingsFile, "Calib", "Green")
	IniWrite(Config.redColor, SettingsFile, "Calib", "Red")
	IniWrite(Config.indicatorX, SettingsFile, "Calib", "X")
	IniWrite(Config.indicatorY, SettingsFile, "Calib", "Y")
}

LoadSettings() {
	global Config, SettingsFile
	if !FileExist(SettingsFile)
		return
	Config.greenColor := IniRead(SettingsFile, "Calib", "Green", "")
	Config.redColor := IniRead(SettingsFile, "Calib", "Red", "")
	Config.indicatorX := IniRead(SettingsFile, "Calib", "X", "0")
	Config.indicatorY := IniRead(SettingsFile, "Calib", "Y", "0")
}
