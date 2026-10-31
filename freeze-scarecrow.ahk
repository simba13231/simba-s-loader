#Requires AutoHotkey v2.0
#SingleInstance Force
#UseHook
#MaxThreadsPerHotkey 1
DllCall("SetProcessDpiAwarenessContext", "ptr", -4, "ptr")
CoordMode "Pixel", "Screen"
CoordMode "Mouse", "Screen"

; ============================================================
;  CALIBRATED FROM IN-GAME SCREENSHOTS:
;    WALK indicator   = 0x5AFF78 (green)
;    FROZEN indicator = 0xFF3728 (red)
;  colorVariation is the per-channel tolerance (leverage):
;    50 means each R/G/B channel can drift +-50 and still match.
;  If the game ever changes shades, press F8 (probe mode) and
;  read the raw color straight off the GUI, then paste it below.
; ============================================================
global Config := {
        walkKey: "w",
        indicatorX: 842,
        indicatorY: 155,
        greenColor: 0x5AFF78,   ; WALK indicator (exact, from screenshot)
        redColor: 0xFF3728,     ; FROZEN indicator (exact red, from screenshot)
        colorVariation: 50,
        boxSize: 10,         ; half-width of the scan box around the indicator point
        pollMs: 60,
        running: false,
        walking: false,
        probing: false,
        status: "Stopped"
}

; ---------- GUI ----------
MainGui := Gui("+AlwaysOnTop", "Freeze / Scarecrow Macro v2.1")
MainGui.SetFont("s10", "Segoe UI")
MainGui.AddText("w340", "Scan point: " Config.indicatorX ", " Config.indicatorY)
MainGui.AddText("w340", "F6 = Start   |   F7 = Stop   |   F8 = Color probe")
global StatusText := MainGui.AddText("w340", "Status: Stopped")
MainGui.Show()

F6::StartMacro()
F7::StopMacro()
F8::ToggleProbe()

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

; ---------- F8 probe: shows the real color under the scan point ----------
; Use it to calibrate: hover the game so the indicator sits at the scan
; point, toggle F8, watch "raw:" change, copy the hex into Config above.
ToggleProbe() {
        global Config
        Config.probing := !Config.probing
        if Config.probing {
                SetStatus("Probe ON - reading colors...")
                SetTimer(ProbeLoop, 200)
        } else {
                SetTimer(ProbeLoop, 0)
                SetStatus("Probe off")
        }
}

ProbeLoop() {
        global Config
        raw := ""
        try raw := PixelGetColor(Config.indicatorX, Config.indicatorY)
        isG := FindColor(Config.indicatorX - Config.boxSize, Config.indicatorY - Config.boxSize,
                         Config.indicatorX + Config.boxSize, Config.indicatorY + Config.boxSize,
                         Config.greenColor, Config.colorVariation)
        isR := FindColor(Config.indicatorX - Config.boxSize, Config.indicatorY - Config.boxSize,
                         Config.indicatorX + Config.boxSize, Config.indicatorY + Config.boxSize,
                         Config.redColor, Config.colorVariation)
        match := isG && isR ? "BOTH (bad config!)" : isG ? "matches GREEN" : isR ? "matches RED" : "matches NEITHER"
        SetStatus("PROBE raw:" (raw = "" ? "?" : raw) "  |  " match)
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
