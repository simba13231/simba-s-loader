#Requires AutoHotkey v2.0
#SingleInstance Force
#UseHook
#MaxThreadsPerHotkey 1
DllCall("SetProcessDpiAwarenessContext", "ptr", -4, "ptr")
CoordMode "Pixel", "Screen"
CoordMode "Mouse", "Screen"
SendMode "Input"
SetKeyDelay -1, -1

; ============================================================
;  Freeze / Scarecrow Macro v2.2 (diagnostic edition)
;
;  CALIBRATED FROM IN-GAME SCREENSHOTS:
;    WALK indicator   = 0x5AFF78 (green)
;    FROZEN indicator = 0xFF3728 (red)
;
;  v2.2 changes:
;   - scans a WIDE region around the indicator point (not just
;     a 21px box), so small position drift no longer kills it
;   - heartbeat: while green, W is re-affirmed every 800ms so
;     games that "eat" synthetic holds keep walking
;   - status shows WHERE the color was found: (x,y)
;   - F8 probe: raw pixel + whether green/red exist in region
;   - F9 auto-recalibrate: finds green/red in the wide region
;     and re-centers the scan point there
;
;  If input still does nothing in-game: right-click the script
;  / loader and "Run as administrator", and use borderless or
;  windowed mode (not exclusive fullscreen).
; ============================================================
global Config := {
        walkKey: "w",
        indicatorX: 842,
        indicatorY: 155,
        greenColor: 0x5AFF78,   ; WALK indicator (exact, from screenshot)
        redColor: 0xFF3728,     ; FROZEN indicator (exact red, from screenshot)
        colorVariation: 50,     ; per-channel tolerance (leverage)
        regionRx: 120,          ; wide-scan half-width around indicator point
        regionRy: 70,           ; wide-scan half-height
        pollMs: 60,
        refreshMs: 800,         ; heartbeat interval while walking
        running: false,
        walking: false,
        probing: false,
        lastRefresh: 0,
        status: "Stopped"
}

; ---------- GUI ----------
MainGui := Gui("+AlwaysOnTop", "Freeze / Scarecrow Macro v2.2")
MainGui.SetFont("s10", "Segoe UI")
MainGui.AddText("w360", "Scan point: " Config.indicatorX ", " Config.indicatorY "  (region +" Config.regionRx "x" Config.regionRy ")")
MainGui.AddText("w360", "F6 = Start   F7 = Stop   F8 = Probe   F9 = Auto-recal")
global StatusText := MainGui.AddText("w360", "Status: Stopped")
MainGui.Show()

F6::StartMacro()
F7::StopMacro()
F8::ToggleProbe()
F9::AutoRecal()

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

ScanRegion(&left, &top, &right, &bottom) {
        global Config
        left := Config.indicatorX - Config.regionRx
        top := Config.indicatorY - Config.regionRy
        right := Config.indicatorX + Config.regionRx
        bottom := Config.indicatorY + Config.regionRy
}

WatchLoop() {
        global Config
        if !Config.running
                return

        ScanRegion(&left, &top, &right, &bottom)
        isGreen := FindColor(&gx, &gy, left, top, right, bottom, Config.greenColor, Config.colorVariation)
        isRed := FindColor(&rx, &ry, left, top, right, bottom, Config.redColor, Config.colorVariation)

        if (isGreen && !isRed) {
                HoldWalk(gx, gy)
        } else if (isRed && !isGreen) {
                ReleaseWalk(rx, ry)
        }
        ; neither/both matched (mid-transition): keep current state
}

FindColor(&fx, &fy, left, top, right, bottom, color, variation) {
        try {
                PixelSearch(&fx, &fy, left, top, right, bottom, color, variation)
                return true
        } catch {
                return false
        }
}

HoldWalk(x := 0, y := 0) {
        global Config
        now := A_TickCount
        if !Config.walking {
                Config.walking := true
                Config.lastRefresh := now
                Send("{" Config.walkKey " down}")
                SetStatus("Walking (green) @ " x "," y)
        } else if (now - Config.lastRefresh >= Config.refreshMs) {
                Config.lastRefresh := now
                Send("{" Config.walkKey " down}")     ; heartbeat re-affirm
                SetStatus("Walking (green) @ " x "," y " [hb]")
        }
}

ReleaseWalk(x := 0, y := 0) {
        global Config
        Config.lastRefresh := 0
        if !Config.walking {
                SetStatus("Frozen (red) @ " x "," y)
                return
        }
        Config.walking := false
        Send("{" Config.walkKey " up}")
        SetStatus("Frozen (red) @ " x "," y)
}

; ---------- F8 probe: live color readout ----------
ToggleProbe() {
        global Config
        Config.probing := !Config.probing
        if Config.probing {
                SetStatus("Probe ON...")
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
        ScanRegion(&left, &top, &right, &bottom)
        g := FindColor(&gx, &gy, left, top, right, bottom, Config.greenColor, Config.colorVariation)
        r := FindColor(&rx, &ry, left, top, right, bottom, Config.redColor, Config.colorVariation)
        gTxt := g ? "GREEN @ " gx "," gy : "green: none"
        rTxt := r ? "RED @ " rx "," ry : "red: none"
        SetStatus("PROBE raw:" (raw = "" ? "?" : raw) "  |  " gTxt "  |  " rTxt)
}

; ---------- F9 auto-recalibrate: re-center on what we can actually see ----------
AutoRecal() {
        global Config
        ScanRegion(&left, &top, &right, &bottom)
        if FindColor(&gx, &gy, left, top, right, bottom, Config.greenColor, Config.colorVariation) {
                Config.indicatorX := gx
                Config.indicatorY := gy
                SetStatus("Recal on GREEN -> " gx "," gy)
                return
        }
        if FindColor(&rx, &ry, left, top, right, bottom, Config.redColor, Config.colorVariation) {
                Config.indicatorX := rx
                Config.indicatorY := ry
                SetStatus("Recal on RED -> " rx "," ry)
                return
        }
        SetStatus("Recal failed: neither color in region")
}

SetStatus(msg) {
        global Config, StatusText
        Config.status := msg
        try StatusText.Text := "Status: " msg
}
