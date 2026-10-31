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
;  Freeze / Scarecrow Macro v2.4
;
;  CALIBRATED FROM IN-GAME SCREENSHOTS:
;    WALK indicator   = 0x5AFF78 (green)
;    FROZEN indicator = 0xFF3728 (red, separate UI element
;                     that can sit at a different screen spot)
;
;  v2.4 logic (region scan + green priority):
;    - scan the region around the scan point for GREEN first;
;      if green is visible ANYWHERE in region -> hold W
;    - else if RED is visible anywhere in region -> release W
;    - else keep current state
;    (green priority kills the "red UI next to green" problem;
;     region scan catches red even at a different spot)
;
;  v2.4 hardening:
;    - startup validation: every numeric Config key is checked;
;      a broken value names the exact key instead of crashing
;      mid-loop with "Expected a Number but got an empty string"
;    - all region math goes through RegionBox() - no inline
;      arithmetic anywhere else
;    - heartbeat re-affirms W every 800ms while walking
;
;  F6 start | F7 stop | F8 probe | F9 auto-recal
;  If input does nothing in-game: run as administrator and
;  prefer borderless/windowed over exclusive fullscreen.
; ============================================================
global Config := {
        walkKey: "w",
        indicatorX: 842,
        indicatorY: 155,
        greenColor: 0x5AFF78,
        redColor: 0xFF3728,
        colorVariation: 50,
        regionRx: 120,
        regionRy: 70,
        pollMs: 60,
        refreshMs: 800,
        running: false,
        walking: false,
        probing: false,
        lastRefresh: 0,
        status: "Stopped"
}

; ---------- startup validation ----------
ValidateConfig() {
        global Config
        numericKeys := ["indicatorX", "indicatorY", "greenColor", "redColor",
                "colorVariation", "regionRx", "regionRy", "pollMs", "refreshMs"]
        for _, key in numericKeys {
                v := Config.%key%
                if !IsNumber(v) {
                        shown := (v = "") ? "EMPTY STRING" : ("[" v "] of type " Type(v))
                        MsgBox("Config key '" key "' is invalid: " shown
                                . "`n`nFix the value in the config block.", "Simba Macro - bad config", "Icon!")
                        ExitApp()
                }
        }
}
ValidateConfig()

; ---------- GUI ----------
MainGui := Gui("+AlwaysOnTop", "Freeze / Scarecrow Macro v2.4")
MainGui.SetFont("s10", "Segoe UI")
MainGui.AddText("w380", "Scan point: " Config.indicatorX ", " Config.indicatorY "  region +" Config.regionRx "x" Config.regionRy)
MainGui.AddText("w380", "F6 = Start   F7 = Stop   F8 = Probe   F9 = Auto-recal")
global StatusText := MainGui.AddText("w380", "Status: Stopped")
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

; ---------- single source of region math ----------
RegionBox(&left, &top, &right, &bottom) {
        global Config
        left := Integer(Config.indicatorX) - Integer(Config.regionRx)
        top := Integer(Config.indicatorY) - Integer(Config.regionRy)
        right := Integer(Config.indicatorX) + Integer(Config.regionRx)
        bottom := Integer(Config.indicatorY) + Integer(Config.regionRy)
}

; ---------- core decision loop ----------
WatchLoop() {
        global Config
        if !Config.running
                return

        RegionBox(&left, &top, &right, &bottom)
        ; GREEN has priority - if the walk indicator is visible at all, walk
        if FindColor(&gx, &gy, left, top, right, bottom, Config.greenColor, Config.colorVariation) {
                HoldWalk(gx, gy)
                return
        }
        ; no green anywhere -> red means frozen
        if FindColor(&rx, &ry, left, top, right, bottom, Config.redColor, Config.colorVariation) {
                ReleaseWalk(rx, ry)
        }
        ; neither visible -> mid-transition, keep current state
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
                Send("{" Config.walkKey " down}")
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
        try raw := PixelGetColor(Integer(Config.indicatorX), Integer(Config.indicatorY))
        RegionBox(&left, &top, &right, &bottom)
        g := FindColor(&gx, &gy, left, top, right, bottom, Config.greenColor, Config.colorVariation)
        r := FindColor(&rx, &ry, left, top, right, bottom, Config.redColor, Config.colorVariation)
        gTxt := g ? "GREEN @ " gx "," gy : "green: none in region"
        rTxt := r ? "RED @ " rx "," ry : "red: none in region"
        SetStatus("PROBE center:" (raw = "" ? "?" : raw) " | " gTxt " | " rTxt)
}

; ---------- F9 auto-recalibrate ----------
AutoRecal() {
        global Config
        RegionBox(&left, &top, &right, &bottom)
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
