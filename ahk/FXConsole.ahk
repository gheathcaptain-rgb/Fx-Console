#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

; FX Console — standalone AutoHotkey v2 palette.
; This source recreates the FX Palette visual language used by the UXP/web UI.
; Replace LoadCatalog() with the catalog bridge used by your Premiere installation.

SetTitleMatchMode 2
CoordMode "Mouse", "Screen"

APP_TITLE := "FX Console"
W := 384
BAR_H := 44
ROW_H := 31
HDR_H := 26
MAX_ROWS := 8
BG := "1E1F22"
LIST_BG := "18191B"
BLUE := "0078D7"

items := [
    {name:"Fast Blur", kind:"Video", group:"Effects", favorite:true},
    {name:"CC Radial Fast Blur", kind:"Video", group:"Effects", favorite:false},
    {name:"Bilateral Blur", kind:"Video", group:"Effects", favorite:false},
    {name:"Box Blur", kind:"Video", group:"Effects", favorite:false},
    {name:"Camera Lens Blur", kind:"Video", group:"Effects", favorite:false},
    {name:"CC Cross Blur", kind:"Video", group:"Effects", favorite:false},
    {name:"Gaussian Blur", kind:"Video", group:"Effects", favorite:false},
    {name:"Studio Reverb", kind:"Audio", group:"Effects", favorite:false},
    {name:"Angry Face (Colour)", kind:"Preset", group:"Presets", favorite:false},
    {name:"Blue Steel", kind:"Preset", group:"Presets", favorite:false},
    {name:"Film Fade Clean", kind:"Preset", group:"Presets", favorite:false},
    {name:"Soft Glow 35mm", kind:"Preset", group:"Presets", favorite:false}
]
LoadCatalog()

query := ""
filteredFavorites := false
results := []
selected := 1
scrollStart := 1
rowControls := []
rowIndexByHwnd := Map()
opened := false
lastToggle := 0
lastShown := 0
lastBack := 0
lastActivity := A_TickCount
isDragging := false
idleTimer := 0
closeOnOutside := true
closeAfterApply := true
shortcutCloses := false
settingsOpen := false
isRendering := false

mainGui := Gui("-Caption +AlwaysOnTop +ToolWindow +Border", APP_TITLE)
mainGui.BackColor := BG
mainGui.MarginX := 0
mainGui.MarginY := 0
mainGui.SetFont("s10 cF3F4F6", "Segoe UI")
mainGui.OnEvent("Escape", (*) => HidePalette())
mainGui.OnEvent("Close", (*) => HidePalette())
mainGui.OnEvent("ContextMenu", (*) => 1) ; deliberately suppress all context menus

; Header controls: 384 x 44, no frame or outer padding.
mainGui.AddText("x0 y0 w384 h44 Background" BG " c32343A", "")
mainGui.AddText("x11 y11 w20 h22 BackgroundTrans cA8ACB6 Center", "⌕")
search := mainGui.AddEdit("x38 y8 w202 h28 -E0x200 Background" BG " cF3F4F6")
search.SetFont("s11.5 w600", "Segoe UI")
placeholder := mainGui.AddText("x39 y8 w200 h28 BackgroundTrans c6E717A +0x200", "Fx")
placeholder.OnEvent("Click", (*) => search.Focus())
search.OnEvent("Change", (*) => SearchChanged(true))
search.OnEvent("Focus", (*) => Touch())
search.OnEvent("ContextMenu", (*) => 1)

buttonSpecs := [
    ["◉", "Snapshot"], ["▦", "Gallery"], ["↓", "Export"], ["⚙", "Settings"], ["➤", "Apply"]
]
buttonX := 244
for spec in buttonSpecs {
    b := mainGui.AddText("x" buttonX " y9 w26 h26 BackgroundTrans cA2A6B0 Center +0x200", spec[1])
    b.SetFont("s10", "Segoe UI Symbol")
    b.OnEvent("Click", ToolbarHandler.Bind(spec[2]))
    b.OnEvent("ContextMenu", (*) => 1)
    buttonX += 27
}

listGui := Gui("-Caption +AlwaysOnTop +ToolWindow +Border", APP_TITLE " Results")
listGui.BackColor := LIST_BG
listGui.MarginX := 0
listGui.MarginY := 0
listGui.SetFont("s9 cF3F4F6", "Segoe UI")
listGui.OnEvent("Escape", (*) => HidePalette())
listGui.OnEvent("ContextMenu", (*) => 1)

settingsGui := Gui("-Caption +AlwaysOnTop +ToolWindow +Border", APP_TITLE " Settings")
settingsGui.BackColor := "1B1C1F"
settingsGui.MarginX := 9
settingsGui.MarginY := 8
settingsGui.SetFont("s9 cD4D6DC", "Segoe UI")
cbAfter := settingsGui.AddCheckBox("w350 h18", "Close bar after applying effect / preset")
cbAfter.Value := 1
cbOutside := settingsGui.AddCheckBox("w350 h18", "Close bar when clicking outside it")
cbOutside.Value := 1
cbShortcut := settingsGui.AddCheckBox("w350 h18", "Shortcut closes bar if already open")
cbShortcut.Value := 0
settingsGui.AddText("xm y+7 w230 h23 Background2B2E35 cE5E7EB Center +0x200", "Rebuild     Self-Test     Clear")
settingsGui.AddText("xm y+6 w350 h18 BackgroundTrans c6E717A", "Prefixes:  v: Video  ·  a: Audio  ·  p: Presets")
cbOutside.OnEvent("Click", (*) => SetCloseOutside())
cbAfter.OnEvent("Click", (*) => SetCloseAfter())
cbShortcut.OnEvent("Click", (*) => SetShortcutClose())
settingsGui.OnEvent("ContextMenu", (*) => 1)

OnMessage(0x0201, WM_LBUTTONDOWN) ; drag window only when handle moved explicitly
OnMessage(0x0200, WM_MOUSEMOVE) ; hover follows the active row
OnMessage(0x0204, WM_RBUTTONDOWN) ; suppress right-click menus

; Hotkeys are global while this script is running. The main shortcut is debounced
; because Ctrl+Alt+Space can be delivered twice on some keyboard layouts.
^!Space::TogglePalette()
~XButton1::BackButtonPress()
#HotIf opened
!Space::return
!f:: {
    filteredFavorites := !filteredFavorites
    SearchChanged(true)
}
Esc::HidePalette()
RButton::return
Up::MoveSelection(-1)
Down::MoveSelection(1)
PgUp::MoveSelection(-8)
PgDn::MoveSelection(8)
Enter::ApplySelected()
#HotIf

; Outside clicks close the bar, but the click remains directed at Premiere.
SetTimer(WatchOutsideClick, 50)
SetTimer(WatchIdle, 250)

LoadCatalog() {
    ; Intentionally keeps this UI portable. FXConsole.tsv may be placed beside
    ; this script (one entry per line: Video<TAB>Effect name or Preset<TAB>Name).
    global items
    path := A_ScriptDir "\FXConsole.tsv"
    if !FileExist(path)
        return
    loaded := []
    for line in StrSplit(FileRead(path, "UTF-8"), "`n", "`r") {
        parts := StrSplit(Trim(line), "`t")
        if parts.Length < 2 || Trim(parts[2]) = ""
            continue
        kind := Trim(parts[1])
        if kind != "Video" && kind != "Audio" && kind != "Preset"
            continue
        loaded.Push({name:Trim(parts[2]), kind:kind, group:kind = "Preset" ? "Presets" : "Effects", favorite:false})
    }
    if loaded.Length
        items := loaded
}

TogglePalette() {
    global opened, lastToggle, lastShown, lastActivity, mainGui, shortcutCloses
    now := A_TickCount
    if now - lastToggle < 300
        return
    lastToggle := now
    if opened {
        if shortcutCloses {
            HidePalette()
            return
        }
        if now - lastShown < 700 {
            mainGui.Show("NoActivate")
            return
        }
        ; Reinvoke while open: start a fresh search at the cursor, as in AE FX Console.
        ShowPalette()
        return
    }
    if !PremiereRunning() {
        MsgBox("Premiere Pro is not running.", APP_TITLE " — FX Console", "Icon!")
        return
    }
    ShowPalette()
    lastActivity := now
}

ShowPalette() {
    global opened, W, BAR_H, HDR_H, ROW_H, MAX_ROWS, mainGui, listGui, search, settingsOpen, lastActivity, lastShown
    x := 0, y := 0
    MouseGetPos(&mx, &my)
    x := mx - 192
    y := my - 22
    monitor := 1
    Loop MonitorGetCount() {
        MonitorGet(A_Index, &ml, &mt, &mr, &mb)
        if mx >= ml && mx < mr && my >= mt && my < mb {
            monitor := A_Index
            break
        }
    }
    MonitorGetWorkArea(monitor, &left, &top, &right, &bottom)
    x := Max(left, Min(x, right - W))
    y := Max(top, Min(y, bottom - BAR_H - 2 * HDR_H - MAX_ROWS * ROW_H))
    mainGui.Show("x" x " y" y " w" W " h" BAR_H " NoActivate")
    opened := true
    lastShown := A_TickCount
    settingsOpen := false
    search.Value := ""
    SearchChanged(true)
    search.Focus()
    lastActivity := A_TickCount
    SetTimer(WatchOutsideClick, 50)
}

HidePalette(*) {
    global opened, mainGui, listGui, settingsGui, settingsOpen
    opened := false
    settingsOpen := false
    mainGui.Hide()
    listGui.Hide()
    settingsGui.Hide()
}

PremiereRunning() {
    ; Adobe Premiere Pro's main window class is commonly Premiere Pro's
    ; internal CEF/Windows frame. Check process name as a stable fallback.
    return ProcessExist("Adobe Premiere Pro.exe") || WinExist("ahk_exe Adobe Premiere Pro.exe")
}

SearchChanged(resetSelection := false) {
    global query, results, selected, scrollStart, items, filteredFavorites, search, placeholder, opened, settingsOpen, settingsGui, lastActivity, MAX_ROWS
    if !opened
        return
    query := Trim(search.Value)
    placeholder.Opt(query = "" ? "-Hidden" : "+Hidden")
    lastActivity := A_TickCount
    if resetSelection {
        selected := 1
        scrollStart := 1
        if settingsOpen {
            settingsOpen := false
            settingsGui.Hide()
        }
    }
    results := []
    if query != "" {
        scope := "all", term := query
        if RegExMatch(query, "i)^\s*(v|a|p)\s*:\s*(.*)$", &m) {
            prefix := StrLower(m[1])
            scope := prefix = "v" ? "Video" : prefix = "a" ? "Audio" : "Preset"
            term := m[2]
        }
        for item in items {
            if filteredFavorites && !item.favorite
                continue
            if scope != "all" && item.kind != scope
                continue
            if Score(term, item.name) >= 0
                results.Push(item)
        }
        SortResults(results)
        ; FX Palette order is always Presets first, then Effects.
        ordered := []
        for group in ["Presets", "Effects"]
            for item in results
                if item.group = group
                    ordered.Push(item)
        results := ordered
    }
    selected := results.Length ? Min(selected, results.Length) : 1
    scrollStart := results.Length ? Min(scrollStart, Max(1, results.Length - MAX_ROWS + 1)) : 1
    RenderResults()
}

Score(q, text) {
    q := StrLower(Trim(q)), t := StrLower(text)
    if q = ""
        return -1
    if t = q
        return 1000
    if SubStr(t, 1, StrLen(q)) = q
        return 900
    if InStr(t, q)
        return 650
    words := StrSplit(RegExReplace(t, "[&/_-]", " "), A_Space)
    initials := ""
    for word in words {
        if word = ""
            continue
        initials .= SubStr(word, 1, 1)
        if SubStr(word, 1, StrLen(q)) = q
            return 800
    }
    if InStr(initials, q)
        return 500
    ti := 1
    Loop Parse q {
        pos := InStr(t, A_LoopField, false, ti)
        if !pos
            return -1
        ti := pos + 1
    }
    return 200
}

SortResults(rows) {
    ; Stable sorting is not needed for UI behavior; use scores and favorites.
    ; A small insertion sort avoids requiring an external JSON/collections lib.
    Loop rows.Length {
        i := A_Index
        j := i
        while j > 1 && CompareRows(rows[j], rows[j - 1]) > 0 {
            tmp := rows[j - 1]
            rows[j - 1] := rows[j]
            rows[j] := tmp
            j -= 1
        }
    }
}

CompareRows(a, b) {
    global query
    af := a.favorite ? 1 : 0, bf := b.favorite ? 1 : 0
    if af != bf
        return af - bf
    return Score(query, a.name) - Score(query, b.name)
}

RenderResults() {
    global results, selected, scrollStart, rowIndexByHwnd, listGui, mainGui, settingsGui, W, HDR_H, ROW_H, MAX_ROWS, query, isRendering
    if isRendering
        return
    isRendering := true
    try {
        rowIndexByHwnd := Map()
        listGui.Destroy()
        listGui := Gui("-Caption +AlwaysOnTop +ToolWindow +Border", "FX Console Results")
        listGui.BackColor := "18191B"
        listGui.MarginX := 0, listGui.MarginY := 0
        listGui.SetFont("s9 cF3F4F6", "Segoe UI")
        listGui.OnEvent("ContextMenu", (*) => 1)
        if !query {
            listGui.Hide()
            settingsGui.Hide()
            return
        }
        rowsShown := Min(MAX_ROWS, results.Length - scrollStart + 1)
        lastVisible := scrollStart + rowsShown - 1
        visiblePresets := 0, visibleEffects := 0
        for index, item in results {
            if index < scrollStart
                continue
            if index > lastVisible
                break
            if item.group = "Presets"
                visiblePresets += 1
            else
                visibleEffects += 1
        }
        headerCount := (visiblePresets ? 1 : 0) + (visibleEffects ? 1 : 0)
        height := results.Length ? (headerCount * HDR_H + rowsShown * ROW_H) : (2 * HDR_H + 36)
        y := 44
        mainGui.GetPos(&x, &top)
        listGui.Show("x" x " y" (top + y) " w" W " h" height " NoActivate")
        if !results.Length {
            AddHeader(listGui, "#EF4444", "Presets", 0, 0)
            AddHeader(listGui, "#3B82F6", "Effects", 0, HDR_H)
            listGui.AddText("x0 y52 w384 h30 Center c6E717A Background18191B", "no match — try another name")
            return
        }
        groups := ["Presets", "Effects"]
        yOff := 0
        for group in groups {
            count := 0
            for item in results
                if item.group = group
                    count += 1
            if !count
                continue
            AddHeader(listGui, group = "Presets" ? "#EF4444" : "#3B82F6", group, count, yOff)
            yOff += HDR_H
            for index, item in results {
                if index < scrollStart
                    continue
                if index > lastVisible
                    break
                if item.group != group
                    continue
                AddResultRow(listGui, item, index, yOff)
                yOff += ROW_H
            }
        }
    } finally {
        isRendering := false
    }
}

AddHeader(gui, dot, title, count, y) {
    gui.AddText("x0 y" y " w384 h26 Background131417 cE5E7EB", "")
    gui.AddText("x12 y" (y + 4) " w8 h18 c" SubStr(dot, 2) " BackgroundTrans", "●")
    gui.AddText("x34 y" (y + 5) " w220 h18 BackgroundTrans cE5E7EB +0x200", title)
    gui.AddText("x344 y" (y + 5) " w28 h18 BackgroundTrans c9CA3AF Right +0x200", count)
}

AddResultRow(gui, item, index, y) {
    global selected, rowControls, rowIndexByHwnd
    isSelected := index = selected
    bg := isSelected ? "0078D7" : "18191B"
    starColor := item.favorite ? "F2B84B" : (isSelected ? "FFFFFF" : "757882")
    star := gui.AddText("x0 y" y " w30 h31 Background" bg " c" starColor " Center +0x200", item.favorite ? "★" : "☆")
    star.SetFont("s10", "Segoe UI Symbol")
    star.OnEvent("Click", ToggleFavorite.Bind(item))
    rowIndexByHwnd[star.Hwnd] := index
    name := gui.AddText("x30 y" y " w260 h31 Background" bg " c" (isSelected ? "FFFFFF" : "F3F4F6") " +0x200 +0x1000", item.name)
    name.SetFont("s9 w600", "Segoe UI")
    name.OnEvent("Click", SelectAndApply.Bind(index))
    rowIndexByHwnd[name.Hwnd] := index
    tagColor := item.kind = "Preset" ? "FCA5A5" : "93C5FD"
    tag := gui.AddText("x290 y" y " w86 h31 Background" bg " c" (isSelected ? "DBEAFE" : tagColor) " Right +0x200", item.kind)
    tag.OnEvent("Click", SelectAndApply.Bind(index))
    rowIndexByHwnd[tag.Hwnd] := index
}

MoveSelection(delta) {
    global selected, scrollStart, results, MAX_ROWS
    if !results.Length
        return
    selected := Mod(selected - 1 + delta, results.Length) + 1
    if selected < scrollStart
        scrollStart := selected
    else if selected >= scrollStart + MAX_ROWS
        scrollStart := selected - MAX_ROWS + 1
    SearchChanged()
}

SelectAndApply(index, *) {
    global selected
    selected := index
    ApplySelected()
}

ApplySelected(*) {
    global results, selected, closeAfterApply, search
    if results.Length < selected
        return
    ; UXP remains responsible for Premiere's effect API. This UI writes an
    ; apply request file that the companion UXP panel can consume.
    item := results[selected]
    request := '{"name":"' JsonEscape(item.name) '","kind":"' item.kind '"}'
    path := A_ScriptDir "\apply-request.json"
    try {
        if FileExist(path)
            FileDelete(path)
        FileAppend(request, path, "UTF-8")
    }
    if closeAfterApply
        HidePalette()
    else
        search.Focus()
}

JsonEscape(text) {
    text := StrReplace(text, "\", "\\")
    text := StrReplace(text, '"', '\"')
    text := StrReplace(text, "`r", "")
    return StrReplace(text, "`n", "\n")
}

ToggleFavorite(item, *) {
    global filteredFavorites
    item.favorite := !item.favorite
    SearchChanged()
}

ToolbarHandler(action, *) {
    global settingsOpen, settingsGui, mainGui, listGui, closeOnOutside
    if action = "Apply" {
        ApplySelected()
    } else if action = "Settings" {
        settingsOpen := !settingsOpen
        if settingsOpen {
            listGui.Hide()
            mainGui.GetPos(&x, &y)
            settingsGui.Show("x" x " y" (y + 44) " w384 h152 NoActivate")
        } else {
            settingsGui.Hide()
            SearchChanged()
        }
    } else if action = "Snapshot" {
        TrayTip("Snapshot is provided by the UXP panel.", APP_TITLE)
    } else if action = "Gallery" {
        TrayTip("Gallery is provided by the UXP panel.", APP_TITLE)
    } else if action = "Export" {
        TrayTip("Export is provided by the UXP panel.", APP_TITLE)
    }
}

BackButtonPress() {
    global lastBack
    now := A_TickCount
    if now - lastBack <= 400
        TogglePalette()
    lastBack := now
}

WatchOutsideClick() {
    global opened, closeOnOutside, mainGui, listGui, settingsGui
    if !opened || !closeOnOutside
        return
    if GetKeyState("LButton", "P") {
        MouseGetPos(,, &win)
        if win != mainGui.Hwnd && win != listGui.Hwnd && win != settingsGui.Hwnd
            HidePalette()
    }
}

WatchIdle() {
    global opened, query, search, lastActivity
    if !opened
        return
    current := search.Value
    if current != query {
        query := current
        lastActivity := A_TickCount
    }
    if query = "" && A_TimeIdlePhysical >= 5000 && A_TickCount - lastActivity >= 5000
        HidePalette()
}

Touch(*) {
    global lastActivity
    lastActivity := A_TickCount
}

SetCloseOutside() {
    global closeOnOutside, cbOutside
    closeOnOutside := cbOutside.Value
}

SetCloseAfter() {
    global closeAfterApply, cbAfter
    closeAfterApply := cbAfter.Value
}

SetShortcutClose() {
    global shortcutCloses, cbShortcut
    shortcutCloses := cbShortcut.Value
}

WM_LBUTTONDOWN(wParam, lParam, msg, hwnd) {
    global mainGui, opened
    if !opened
        return
    parent := DllCall("GetParent", "Ptr", hwnd, "Ptr")
    if hwnd != mainGui.Hwnd && parent != mainGui.Hwnd
        return
    MouseGetPos(&mx, &my)
    mainGui.GetPos(&wx, &wy)
    ; The search box and toolbar buttons keep their native clicks; the remaining
    ; header area is a Windows caption drag grip (Windows applies its 2px threshold).
    relX := mx - wx
    if my < wy || my > wy + 44 || (relX >= 38 && relX < 240) || (relX >= 244 && relX < 379)
        return
    PostMessage(0x00A1, 2,,, "ahk_id " mainGui.Hwnd) ; WM_NCLBUTTONDOWN / HTCAPTION
}

WM_MOUSEMOVE(wParam, lParam, msg, hwnd) {
    global rowIndexByHwnd, selected, scrollStart, MAX_ROWS, isRendering
    if isRendering || !rowIndexByHwnd.Has(hwnd)
        return
    index := rowIndexByHwnd[hwnd]
    if index = selected
        return
    selected := index
    if selected < scrollStart
        scrollStart := selected
    else if selected >= scrollStart + MAX_ROWS
        scrollStart := selected - MAX_ROWS + 1
    Touch()
    SearchChanged()
}

WM_RBUTTONDOWN(*) {
    return 0
}
