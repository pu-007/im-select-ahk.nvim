#Requires AutoHotkey v2.0
#SingleInstance Off
#NoTrayIcon

; im-select.ahk - CLI tool for Windows IME status detection and switching
; v2: Uses SendMessageTimeoutW + ImmGetDefaultIMEWnd (InputTip technique)
; Fallback to keyboard simulation when IME API fails

Main()

; ============================================================
; IME class - Core IME detection/control via WM_IME_CONTROL
; Reference: https://github.com/Tebayaki/AutoHotkeyScripts
; ============================================================

class IME {
    static timeout := 500

    static GetFocusedWindow() {
        if foreHwnd := WinExist("A") {
            guiThreadInfo := Buffer(A_PtrSize == 8 ? 72 : 48)
            NumPut("uint", guiThreadInfo.Size, guiThreadInfo)
            DllCall("GetGUIThreadInfo",
                "uint", DllCall("GetWindowThreadProcessId", "ptr", foreHwnd, "ptr", 0, "uint"),
                "ptr", guiThreadInfo)
            if focusedHwnd := NumGet(guiThreadInfo, A_PtrSize == 8 ? 16 : 12, "ptr")
                return focusedHwnd
            return foreHwnd
        }
        return 0
    }

    static GetOpenStatus(hwnd := this.GetFocusedWindow()) {
        if !hwnd
            return -1
        imeWnd := DllCall("imm32\ImmGetDefaultIMEWnd", "ptr", hwnd, "ptr")
        if !imeWnd
            return -1
        result := DllCall("SendMessageTimeoutW",
            "ptr", imeWnd, "uint", 0x283, "ptr", 0x5, "ptr", 0,
            "uint", 0, "uint", this.timeout, "ptr*", &status := 0)
        if !result
            return -1
        return status
    }

    static SetOpenStatus(status, hwnd := this.GetFocusedWindow()) {
        if !hwnd
            return false
        imeWnd := DllCall("imm32\ImmGetDefaultIMEWnd", "ptr", hwnd, "ptr")
        if !imeWnd
            return false
        result := DllCall("SendMessageTimeoutW",
            "ptr", imeWnd, "uint", 0x283, "ptr", 0x6, "ptr", status,
            "uint", 0, "uint", this.timeout, "ptr*", 0)
        return result != 0
    }

    static GetConversionMode(hwnd := this.GetFocusedWindow()) {
        if !hwnd
            return -1
        imeWnd := DllCall("imm32\ImmGetDefaultIMEWnd", "ptr", hwnd, "ptr")
        if !imeWnd
            return -1
        result := DllCall("SendMessageTimeoutW",
            "ptr", imeWnd, "uint", 0x283, "ptr", 0x1, "ptr", 0,
            "uint", 0, "uint", this.timeout, "ptr*", &mode := 0)
        if !result
            return -1
        return mode
    }

    static SetConversionMode(mode, hwnd := this.GetFocusedWindow()) {
        if !hwnd
            return false
        imeWnd := DllCall("imm32\ImmGetDefaultIMEWnd", "ptr", hwnd, "ptr")
        if !imeWnd
            return false
        result := DllCall("SendMessageTimeoutW",
            "ptr", imeWnd, "uint", 0x283, "ptr", 0x2, "ptr", mode,
            "uint", 0, "uint", this.timeout, "ptr*", 0)
        return result != 0
    }

    static GetKeyboardLayout(hwnd := this.GetFocusedWindow()) {
        if !hwnd
            return 0
        return DllCall("GetKeyboardLayout",
            "uint", DllCall("GetWindowThreadProcessId", "ptr", hwnd, "ptr", 0, "uint"),
            "ptr")
    }

    static GetInputMode(hwnd := this.GetFocusedWindow()) {
        openStatus := this.GetOpenStatus(hwnd)
        if openStatus = -1
            return ""  ; API failed
        if !openStatus
            return "en"
        convMode := this.GetConversionMode(hwnd)
        if convMode = -1
            return ""  ; API failed
        return (convMode & 1) ? "zh" : "en"
    }

    static SetInputMode(mode, hwnd := this.GetFocusedWindow()) {
        if mode = "en" {
            return this.SetOpenStatus(false, hwnd)
        } else if mode = "zh" {
            this.SetOpenStatus(true, hwnd)
            kl := this.GetKeyboardLayout(hwnd)
            switch kl {
                case 0x08040804:
                    this.SetConversionMode(1025, hwnd)
                case 0x04110411:
                    this.SetConversionMode(9, hwnd)
                default:
                    this.SetConversionMode(1025, hwnd)
            }
            return true
        }
        return false
    }
}

; ============================================================
; Main entry point
; ============================================================

Main() {
    if A_Args.Length = 0 {
        PrintUsage()
        ExitApp 1
    }

    command := A_Args[1]
    toggleKey := "RShift"
    setTarget := ""
    timeout := 500

    ; Parse arguments
    i := 2
    while i <= A_Args.Length {
        arg := A_Args[i]
        if arg = "--key" && i + 1 <= A_Args.Length {
            toggleKey := A_Args[i + 1]
            i += 2
        } else if arg = "--timeout" && i + 1 <= A_Args.Length {
            timeout := Integer(A_Args[i + 1])
            i += 2
        } else if command = "set" && (arg = "en" || arg = "zh") {
            setTarget := arg
            i += 1
        } else {
            i += 1
        }
    }

    IME.timeout := timeout
    stateFile := GetStateFilePath()

    switch command {
        case "get":
            result := IME.GetInputMode()
            if result = "" {
                ; API failed, fallback to state file
                result := ReadState(stateFile)
            } else {
                ; API succeeded, sync state file
                SaveState(stateFile, result)
            }
            WriteStdout(result)

        case "set":
            if setTarget = "" {
                WriteStdout("error: usage: im-select set <en|zh>")
                ExitApp 1
            }
            ; Get current state via API
            current := IME.GetInputMode()
            if current = ""
                current := ReadState(stateFile)

            if current = setTarget {
                WriteStdout(setTarget)
                ExitApp 0
            }

            ; Try IME API first
            IME.SetInputMode(setTarget)
            Sleep 50
            verify := IME.GetInputMode()

            if verify = setTarget {
                ; API succeeded
                SaveState(stateFile, setTarget)
            } else {
                ; API failed or didn't take effect, fallback to key simulation
                SendToggleKey(toggleKey)
                SaveState(stateFile, setTarget)
            }
            WriteStdout(setTarget)

        case "toggle":
            current := IME.GetInputMode()
            if current = ""
                current := ReadState(stateFile)
            newState := (current = "zh") ? "en" : "zh"

            IME.SetInputMode(newState)
            Sleep 50
            verify := IME.GetInputMode()

            if verify = newState {
                SaveState(stateFile, newState)
            } else {
                SendToggleKey(toggleKey)
                SaveState(stateFile, newState)
            }
            WriteStdout(newState)

        case "check":
            RunHealthCheck(toggleKey, stateFile, timeout)

        default:
            PrintUsage()
            ExitApp 1
    }
    ExitApp 0
}

; ============================================================
; State file management (fallback persistence)
; ============================================================

GetStateFilePath() {
    if A_IsCompiled
        return A_ScriptDir "\im-select.state"
    else
        return A_Temp "\im-select.state"
}

ReadState(stateFile) {
    try {
        if FileExist(stateFile) {
            content := Trim(FileRead(stateFile, "UTF-8"))
            if content = "zh" || content = "en"
                return content
        }
    }
    return "en"
}

SaveState(stateFile, state) {
    try {
        f := FileOpen(stateFile, "w", "UTF-8")
        f.Write(state)
        f.Close()
    }
}

; ============================================================
; Keyboard simulation (fallback)
; ============================================================

SendToggleKey(key) {
    try {
        Send "{" key "}"
    } catch as e {
        WriteStdout("error: failed to send key '" key "': " e.Message)
        ExitApp 1
    }
}

; ============================================================
; Health check
; ============================================================

RunHealthCheck(toggleKey, stateFile, timeout) {
    hwnd := IME.GetFocusedWindow()
    hwndOk := hwnd ? "true" : "false"

    ; Test IME API
    openStatus := IME.GetOpenStatus(hwnd)
    openStatusOk := (openStatus != -1) ? "true" : "false"
    convMode := IME.GetConversionMode(hwnd)
    convModeOk := (convMode != -1) ? "true" : "false"
    inputMode := IME.GetInputMode(hwnd)
    apiWorking := (inputMode != "") ? "true" : "false"

    ; IME window
    imeWnd := 0
    if hwnd
        imeWnd := DllCall("imm32\ImmGetDefaultIMEWnd", "ptr", hwnd, "ptr")
    imeWndOk := imeWnd ? "true" : "false"

    ; Keyboard layout
    kl := IME.GetKeyboardLayout(hwnd)
    klHex := Format("0x{:08x}", kl)

    ; Window title
    winTitle := ""
    try winTitle := WinGetTitle("A")
    winTitle := StrReplace(winTitle, '\', '\\')
    winTitle := StrReplace(winTitle, '"', '\"')

    currentState := (inputMode != "") ? inputMode : ReadState(stateFile)
    stateFileExists := FileExist(stateFile) ? "true" : "false"
    sfPath := StrReplace(stateFile, '\', '\\')

    json := '{'
    json .= '"ahk_version":"' A_AhkVersion '",'
    json .= '"mode":"ime_api",'
    json .= '"api_working":' apiWorking ','
    json .= '"foreground_window":' hwndOk ','
    json .= '"foreground_title":"' winTitle '",'
    json .= '"ime_window":' imeWndOk ','
    json .= '"open_status":' openStatus ','
    json .= '"open_status_ok":' openStatusOk ','
    json .= '"conversion_mode":' convMode ','
    json .= '"conversion_mode_ok":' convModeOk ','
    json .= '"keyboard_layout":"' klHex '",'
    json .= '"toggle_key":"' toggleKey '",'
    json .= '"timeout":' timeout ','
    json .= '"state_file":"' sfPath '",'
    json .= '"state_file_exists":' stateFileExists ','
    json .= '"current_state":"' currentState '"'
    json .= '}'

    WriteStdout(json)
}

; ============================================================
; Stdout output
; ============================================================

_InitConsole() {
    DllCall("AttachConsole", "UInt", 0xFFFFFFFF)
    h := DllCall("GetStdHandle", "Int", -11, "Ptr")
    return h
}

WriteStdout(text) {
    static hStdOut := _InitConsole()

    if (!hStdOut || hStdOut = -1) {
        DllCall("AllocConsole")
        hStdOut := DllCall("GetStdHandle", "Int", -11, "Ptr")
    }

    if (!hStdOut || hStdOut = -1)
        return

    utf8Size := StrPut(text, "UTF-8") - 1
    if utf8Size <= 0
        return
    buf := Buffer(utf8Size)
    StrPut(text, buf, "UTF-8")

    written := 0
    DllCall("WriteFile", "Ptr", hStdOut, "Ptr", buf, "UInt", utf8Size, "UInt*", &written, "Ptr", 0)
}

PrintUsage() {
    usage := "im-select - Windows IME mode switcher (v2)`n"
    usage .= "`n"
    usage .= "Usage: im-select.exe <command> [options]`n"
    usage .= "`n"
    usage .= "Commands:`n"
    usage .= "  get            Output current IME mode: 'en' or 'zh'`n"
    usage .= "  set <en|zh>    Switch to specified mode`n"
    usage .= "  toggle         Toggle between Chinese and English`n"
    usage .= "  check          Health check, output diagnostics as JSON`n"
    usage .= "`n"
    usage .= "Options:`n"
    usage .= "  --key <name>   Toggle key for switching (default: RShift)`n"
    usage .= "  --timeout <ms> SendMessage timeout (default: 500)`n"
    WriteStdout(usage)
}
