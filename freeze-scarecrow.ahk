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
;  Freeze / Scarecrow Macro v2.3 (center-pixel edition)
;
;  CALIBRATED FROM IN-GAME SCREENSHOTS + F8 PROBE:
;    WALK indicator   = 0x5AFF78 (green)
;    FROZEN indicator = 0xFF3728 (red)
;
;  WHY v2.3: the probe proved the scan point reads EXACT
;  0x5AFF78, but the 21px box also caught red UI elements
;  sitting near the indicator -> "both colors found" -> the
;  old logic stalled. v2.3 reads the CENTER PIXEL first:
;     center ~= green  -> walk
;     center ~= red    -> freeze
;  and only falls back to a tiny +-6px box scan when the
;  center is mid-transition. Green has priority.
;
;  Heartbeat: while green, W is re-affirmed every 800ms so
;  games that eat synthetic holds keep walking.
;
;  F8 = probe (center raw + region search)   F9 = auto-recal
;  If input does nothing in-game: run as administrator and
;  prefer borderless/windowed over exclusive fullscreen.
; ============================================================
global Config := {
        walkKey: "w",
        indicatorX: 842,
        indicatorY: 155,
        greenColor: 0x5AFF78,   ; WALK indicator (exact, from screenshot)
        redColor: 0xFF3728,     ; FROZEN indicator (exact red, from screenshot)
        colorVariation: 50,     ; max per-channel drift that still counts
        fallbackBox: 6,         ; half-size of the tiny fallback scan box
        regionRx: 120,          ; probe/recal search half-width
        regionRy: 70,           ; probe/recal search half-height
        pollMs: 60,
        refreshMs: 800,         ; heartbeat interval while walking
        running: false,
        walking: false,
        probing: false,
        lastRefresh: 0,
        status: "Stopped"
}

; ---------- GUI ----------
MainGui := Gui("+AlwaysOnTop", "Freeze / Scarecrow Macro v2.3")
MainGui.SetFont("s10", "Segoe UI")
MainGui.AddText("w360", "Scan point: " Config.indicatorX ", " Config.indicatorY " (center pixel)")
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

; ---------- core decision loop ----------
WatchLoop() {
        global Config
        if !Config.running
                return

        ; 1) center pixel decides
        raw := 0
        ok := true
        try
                raw := Integer(PixelGetColor(Config.indicatorX, Config.indicatorY))
        catch
                ok := false
        if ok {
                if (ColorDistance2(raw, Config.greenColor) <= Config.colorVariation) {
                        HoldWalk(Config.indicatorX, Config.indicatorY)
                        return
                }
                if (ColorDistance2(raw, Config.redColor) <= Config.colorVariation) {
                        ReleaseWalk(Config.indicatorX, Config.indicatorY)
                        return
                }
        }

        ; 2) fallback: tiny box scan for mid-transition pixels
        fb := Config.fallbackBox
        left := Config.indicatorX - fb, top := Config.indicatorY - fb
        right := Config.indicatorX + fb, bottom := Config.indicatorY + fb
        g := FindColor(&gx, &gy, left, top, right, bottom, Config.greenColor, Config.colorVariation)
        r := FindColor(&rx, &ry, left, top, right, bottom, Config.redColor, Config.colorVariation)
        if g {
                HoldWalk(gx, gy)
        } else if r {
                ReleaseWalk(rx, ry)
        }
        ; else: genuinely mid-transition -> keep current state
}

ColorDistance2(c, target) {
        dr := Abs(((c >> 16) & 0xFF) - ((target >> 16) & 0xFF))
        dg := Abs(((c >> 8) & 0xFF) - ((target >> 8) & 0xFF))
        db := Abs((c & 0xFF) - (target & 0xFF))
        return Max(dr, dg, db)
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

; ---------- F8 probe ----------
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
        g := FindColor(&gx, &gy, Config.indicatorX - Config.regionRx, Config.indicatorY - Config.regionRy,
                Config.indicatorX + Config.regionRx, Config.indicatorY + Config.regionRy,
                Config.greenColor, Config.colorVariation)
        r := FindColor(&rx, &ry, Config.indicatorX - Config.regionRx, Config.indicatorY - Config.regionRy,
                Config.indicatorX + Config.regionRx, Config.indicatorY + Config.regionRy,
                Config.redColor, Config.colorVariation)
        gTxt := g ? "GREEN @ " gx "," gy : "green: none"
        rTxt := r ? "RED @ " rx "," ry : "red: none"
        SetStatus("PROBE center:" (raw = "" ? "?" : raw) "  |  " gTxt "  |  " rTxt)
}

; ---------- F9 auto-recalibrate ----------
AutoRecal() {
        global Config
        left := Config.indicatorX - Config.regionRx, top := Config.indicatorY - Config.regionRy
        right := Config.indicatorX + Config.regionRx, bottom := Config.indicatorY + Config.regionRy
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
