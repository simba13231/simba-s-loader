#Requires AutoHotkey v2.0
#SingleInstance Force
; ============================================================
;  Simba Loader v1
;  - reads freeze-scarecrow.enc (SIMBA1 | salt16 | iv16 | AES-256-CBC ct)
;  - asks for the passphrase
;  - verifies it against passphrase.hash (SHA-256 of PBKDF2 verifier)
;  - derives the AES key with PBKDF2-HMAC-SHA256 (200k iterations)
;  - decrypts in memory via Windows CNG (bcrypt.dll) and runs the script
;
;  The repo contains NO key material. passphrase.hash is a verifier,
;  it cannot decrypt anything.
;  Keep ITERATIONS and VERIFY_SALT in sync with encrypt.py.
; ============================================================

global ITERATIONS := 200000
global VERIFY_SALT := "simba-verify-salt-v1"

encPath := A_ScriptDir "\freeze-scarecrow.enc"
hashPath := A_ScriptDir "\passphrase.hash"

if !FileExist(encPath) {
        MsgBox("freeze-scarecrow.enc not found next to the loader.", "Simba Loader", "Icon!")
        ExitApp()
}

; ---------- read blob ----------
b64 := Trim(FileRead(encPath, "UTF-8"))
raw := B64Decode(b64)
if !(raw is Buffer) || (raw.Size < 38 + 16) || (StrGet(raw.Ptr, 6, "CP0") != "SIMBA1") {
        MsgBox("freeze-scarecrow.enc is not a valid SIMBA1 blob.", "Simba Loader", "Icon!")
        ExitApp()
}
saltPtr := raw.Ptr + 6
ivBuf := Buffer(16, 0)
DllCall("RtlMoveMemory", "ptr", ivBuf.Ptr, "ptr", raw.Ptr + 22, "uptr", 16)
ctPtr := raw.Ptr + 38
ctLen := raw.Size - 38

; ---------- ask for passphrase ----------
pass := ""
Loop 3 {
        ib := InputBox("Enter passphrase (attempt " A_Index "/3):", "Simba Loader", "W340 H132 Password")
        if (ib.Result != "OK")
                ExitApp()
        pass := ib.Value
        if (pass = "") {
                MsgBox("Passphrase cannot be empty.", "Simba Loader", "Icon!")
                continue
        }
        stored := ""
        if FileExist(hashPath)
                stored := StrLower(Trim(FileRead(hashPath, "UTF-8")))
        if (stored = "") || (StrLower(PassVerifier(pass)) = stored)
                break
        if (A_Index = 3) {
                MsgBox("Wrong passphrase. Exiting.", "Simba Loader", "Icon!")
                ExitApp()
        }
        MsgBox("Wrong passphrase, try again.", "Simba Loader", "Icon!")
}

; ---------- derive key + decrypt ----------
passBuf := Buffer(StrPut(pass, "UTF-8"), 0)
StrPut(pass, passBuf, "UTF-8")
passLen := passBuf.Size - 1        ; exclude NUL terminator

key := PBKDF2(passBuf.Ptr, passLen, saltPtr, 16, ITERATIONS, 32)
if !(key is Buffer) {
        MsgBox("Key derivation failed (bcrypt error).", "Simba Loader", "Icon!")
        ExitApp()
}

ptBuf := AESCBCDecrypt(key, ivBuf, ctPtr, ctLen)
if !(ptBuf is Buffer) {
        MsgBox("Decryption failed - most likely a wrong passphrase.", "Simba Loader", "Icon!")
        ExitApp()
}

scriptText := StrGet(ptBuf.Ptr, ptBuf.Size, "UTF-8")
if (InStr(scriptText, "#Requires") != 1) {
        MsgBox("Decrypted payload does not look right - wrong passphrase?", "Simba Loader", "Icon!")
        ExitApp()
}

; ---------- write temp + run ----------
tempPath := A_Temp "\simba_decrypted.ahk"
try FileDelete(tempPath)
FileAppend(scriptText, tempPath, "UTF-8")
RunWait('"' tempPath '"')
try FileDelete(tempPath)
ExitApp()

; ============================================================
;  Crypto helpers (Windows CNG via bcrypt.dll)
; ============================================================

B64Decode(str) {
        size := 0
        r := DllCall("crypt32\CryptStringToBinaryW",
                "wstr", str, "uint", StrLen(str), "uint", 0x06,
                "ptr", 0, "uint*", &size := 0, "ptr", 0, "ptr", 0, "int")
        if (r = 0) || (size = 0)
                return 0
        buf := Buffer(size, 0)
        r := DllCall("crypt32\CryptStringToBinaryW",
                "wstr", str, "uint", StrLen(str), "uint", 0x06,
                "ptr", buf.Ptr, "uint*", &size := size, "ptr", 0, "ptr", 0, "int")
        return r = 0 ? 0 : buf
}

; SHA256 of PBKDF2(passphrase, VERIFY_SALT) -> hex string
PassVerifier(pass) {
        pb := Buffer(StrPut(pass, "UTF-8"), 0)
        StrPut(pass, pb, "UTF-8")
        vb := Buffer(StrPut(VERIFY_SALT, "UTF-8"), 0)
        StrPut(VERIFY_SALT, vb, "UTF-8")
        dk := PBKDF2(pb.Ptr, pb.Size - 1, vb.Ptr, StrLen(VERIFY_SALT), ITERATIONS, 32)
        if !(dk is Buffer)
                return ""
        return SHA256Hex(dk.Ptr, dk.Size)
}

PBKDF2(passPtr, passLen, saltPtr, saltLen, iters, outLen) {
        hPrf := 0
        if DllCall("bcrypt\BCryptOpenAlgorithmProvider", "ptr*", &hPrf := 0,
                "wstr", "SHA256", "wstr", "", "uint", 0, "int") != 0
                return 0
        out := Buffer(outLen, 0)
        r := DllCall("bcrypt\BCryptDeriveKeyPBKDF2",
                "ptr", hPrf,
                "ptr", passPtr, "uint", passLen,
                "ptr", saltPtr, "uint", saltLen,
                "int64", iters,
                "ptr", out.Ptr, "uint", outLen,
                "uint", 0, "int")
        DllCall("bcrypt\BCryptCloseAlgorithmProvider", "ptr", hPrf, "uint", 0)
        return r = 0 ? out : 0
}

SHA256Hex(ptr, len) {
        hAlg := 0
        if DllCall("bcrypt\BCryptOpenAlgorithmProvider", "ptr*", &hAlg := 0,
                "wstr", "SHA256", "wstr", "", "uint", 0, "int") != 0
                return ""
        hashBuf := Buffer(32, 0)
        ok := DllCall("bcrypt\BCryptHashData", "ptr", hAlg, "ptr", ptr, "uint", len, "uint", 0, "int") = 0
        if ok
                ok := DllCall("bcrypt\BCryptFinishHash", "ptr", hAlg, "ptr", hashBuf.Ptr, "uint", 32, "uint", 0, "int") = 0
        DllCall("bcrypt\BCryptCloseAlgorithmProvider", "ptr", hAlg, "uint", 0)
        if !ok
                return ""
        hex := ""
        Loop 32
                hex .= Format("{:02x}", NumGet(hashBuf, A_Index - 1, "uchar"))
        return hex
}

AESCBCDecrypt(keyBuf, ivBuf, ctPtr, ctLen) {
        hAlg := 0
        if DllCall("bcrypt\BCryptOpenAlgorithmProvider", "ptr*", &hAlg := 0,
                "wstr", "AES", "wstr", "", "uint", 0, "int") != 0
                return 0
        ; set CBC chaining mode
        if DllCall("bcrypt\BCryptSetProperty", "ptr", hAlg, "wstr", "ChainingMode",
                "wstr", "ChainingModeCBC", "uint", 32, "uint", 0, "int") != 0 {
                DllCall("bcrypt\BCryptCloseAlgorithmProvider", "ptr", hAlg, "uint", 0)
                return 0
        }
        ; key object
        cbObj := 0, cbRes := 0
        if DllCall("bcrypt\BCryptGetProperty", "ptr", hAlg, "wstr", "ObjectLength",
                "uint*", &cbObj := 0, "uint", 4, "uint*", &cbRes := 0, "uint", 0, "int") != 0 {
                DllCall("bcrypt\BCryptCloseAlgorithmProvider", "ptr", hAlg, "uint", 0)
                return 0
        }
        keyObj := Buffer(cbObj, 0)
        hKey := 0
        if DllCall("bcrypt\BCryptGenerateSymmetricKey", "ptr", hAlg, "ptr*", &hKey := 0,
                "ptr", keyObj.Ptr, "uint", cbObj,
                "ptr", keyBuf.Ptr, "uint", keyBuf.Size, "uint", 0, "int") != 0 {
                DllCall("bcrypt\BCryptCloseAlgorithmProvider", "ptr", hAlg, "uint", 0)
                return 0
        }
        out := Buffer(ctLen, 0)
        cbOut := 0
        r := DllCall("bcrypt\BCryptDecrypt",
                "ptr", hKey,
                "ptr", ctPtr, "uint", ctLen,
                "ptr", 0,
                "ptr", ivBuf.Ptr, "uint", 16,
                "ptr", out.Ptr, "uint", out.Size,
                "uint*", &cbOut := 0,
                "uint", 1,          ; BCRYPT_BLOCK_PADDING (PKCS7)
                "int")
        DllCall("bcrypt\BCryptDestroyKey", "ptr", hKey)
        DllCall("bcrypt\BCryptCloseAlgorithmProvider", "ptr", hAlg, "uint", 0)
        if (r != 0) || (cbOut = 0) || (cbOut > ctLen)
                return 0
        return ResizeAndCopy(out, cbOut)
}

ResizeAndCopy(buf, newSize) {
        nb := Buffer(newSize, 0)
        DllCall("RtlMoveMemory", "ptr", nb.Ptr, "ptr", buf.Ptr, "uptr", newSize)
        return nb
}
