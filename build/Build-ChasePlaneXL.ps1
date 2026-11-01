# Builds the ChasePlane profiles for every Stream Deck model (Mini, 15-key, Neo, Plus, XL, Plus XL, Studio):
#   - one plugin profile per model, bundled in the .streamDeckPlugin (needs the plugin; uses the ChasePlane Bridge)
#   - one hotkeys-only profile per model in hotkeys-only\ (no plugin needed)
#   - chaseplane-keymap.csv (keyboard commands the profiles use)
# XL layout: row 0 = tab bar (VIEWS | WORLD | FLY CAM | FX) + 4 always-available keys.
# 15-key: row 0 = 5 tabs. Neo / Plus / Mini: no room for a tab bar, so the last key is a "next page" key.
# Run:  powershell -ExecutionPolicy Bypass -File build\Build-ChasePlaneXL.ps1
# Optional: set CP_PREVIEW_DIR to also write one preview sheet per model (all pages stacked).
# Keep this file ASCII-only (Windows PowerShell 5.1 reads BOM-less UTF-8 as ANSI).
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Numerics
Add-Type -AssemblyName System.IO.Compression

$Root     = Split-Path $PSScriptRoot -Parent
$CsvFile  = Join-Path $Root 'chaseplane-keymap.csv'
$Preview  = if ($env:CP_PREVIEW_DIR) { $env:CP_PREVIEW_DIR } else { $null }
$GotoBase    = 1                # "Go to Page" numbering of the Stream Deck app (1 = first page; set to 0 if tabs open the wrong page)

# ---------------------------------------------------------------- ids
$Alpha = '0123456789ABCDEFGHIJKLMNOPQRSTUV'
function Encode-Id([string]$uuid) {
    $hex = $uuid.Replace('-', '')
    $v = [System.Numerics.BigInteger]::Parse('0' + $hex, [System.Globalization.NumberStyles]::HexNumber) * 4
    $c = New-Object char[] 26
    for ($i = 25; $i -ge 0; $i--) {
        $c[$i] = $Alpha[[int][System.Numerics.BigInteger]::Remainder($v, 32)]
        $v = [System.Numerics.BigInteger]::Divide($v, 32)
    }
    (-join $c) + 'Z'
}
if ((Encode-Id '95318099-2182-4712-8c5a-83b55ca4630d') -ne 'IKOO1691G93H532QGEQLP9331KZ') { throw 'Encode-Id self-test failed' }
function New-Uuid { [guid]::NewGuid().ToString() }

# ---------------------------------------------------------------- hotkeys
function Get-KeyInfo([string]$name) {
    if ($name -match '^[A-Z0-9]$') { $c = [int][char]$name; return @{ vk = $c; qt = $c } }
    if ($name -match '^F(\d+)$')   { $n = [int]$Matches[1]; return @{ vk = 111 + $n; qt = 16777264 + $n - 1 } }
    switch ($name) {
        'End'    { return @{ vk = 35; qt = 16777233 } }
        'PageUp' { return @{ vk = 33; qt = 16777238 } }
        'Space'  { return @{ vk = 32; qt = 32 } }
    }
    throw "Unknown key $name"
}
function New-Hotkey([string]$combo) {
    $parts = $combo.Split('+'); $key = $parts[$parts.Length - 1]
    $shift = $parts -contains 'Shift'; $ctrl = $parts -contains 'Ctrl'; $alt = $parts -contains 'Alt'
    $k = Get-KeyInfo $key
    $mods = 0; if ($shift) { $mods += 1 }; if ($ctrl) { $mods += 2 }; if ($alt) { $mods += 4 }
    [ordered]@{ KeyCmd = $false; KeyCtrl = $ctrl; KeyModifiers = $mods; KeyOption = $alt; KeyShift = $shift
                NativeCode = $k.vk; QTKeyCode = $k.qt; VKeyCode = $k.vk }
}
function New-EmptyHotkey {
    [ordered]@{ KeyCmd = $false; KeyCtrl = $false; KeyModifiers = 0; KeyOption = $false; KeyShift = $false
                NativeCode = 146; QTKeyCode = 33554431; VKeyCode = -1 }
}

# ---------------------------------------------------------------- ChasePlane commands
# Bindings that already exist in ChasePlane's default control_mappings (read from user_settings.json).
$Existing = @{
    CAM_TOGGLE_IN_OUT = 'End'
    CAM_PREV_VIEW = 'Shift+G';  CAM_NEXT_VIEW = 'Shift+T'
    CAM_QUICK_VIEW_LEFT = 'Shift+H'; CAM_QUICK_VIEW_RIGHT = 'Shift+F'
    CAM_RESET = 'Shift+Space';  CAM_FLASHLIGHT_TOGGLE = 'Alt+F'
    CAM_MOVE_L = 'Shift+A'; CAM_MOVE_R = 'Shift+D'; CAM_MOVE_F = 'Shift+W'; CAM_MOVE_B = 'Shift+S'
    CAM_MOVE_U = 'Shift+E'; CAM_MOVE_D = 'Shift+Q'
    CAM_ZOOM_IN = 'Shift+O'; CAM_ZOOM_OUT = 'Shift+U'
    CAM_ROT_L = 'Shift+J'; CAM_ROT_R = 'Shift+L'; CAM_ROT_U = 'Shift+I'; CAM_ROT_D = 'Shift+K'
    CAM_BOOST_SET = 'PageUp'
}
# New bindings (Ctrl+Alt + key). Pinned so a layout change never moves a key that is already set up in ChasePlane.
$NewKeys = [ordered]@{
    CAM_NEAR_TOWER               = 'Ctrl+Alt+F1'
    CAM_SET_ONBOARD              = 'Ctrl+Alt+F2'
    CAM_NEAR_RUNWAY              = 'Ctrl+Alt+F3'
    CAM_SET_OUTSIDE              = 'Ctrl+Alt+F4'
    CAM_PREV_GROUP               = 'Ctrl+Alt+F5'
    CAM_NEAR_PARKING             = 'Ctrl+Alt+F6'
    CAM_QUICK_VIEW_UP            = 'Ctrl+Alt+F7'
    CAM_SET_WORLD                = 'Ctrl+Alt+F8'
    CAM_NEXT_GROUP               = 'Ctrl+Alt+F9'
    CAM_NEAR_SPOTTING            = 'Ctrl+Alt+F10'
    CAM_QUICK_VIEW_DOWN          = 'Ctrl+Alt+F11'
    CAM_SET_CINEMATIC            = 'Ctrl+Alt+F13'
    CAM_SMART_VIEW               = 'Ctrl+Alt+F14'
    CAM_NEAR_TRAFFIC             = 'Ctrl+Alt+F15'
    CAM_QUICK_VIEW_BEHIND        = 'Ctrl+Alt+F16'
    CAM_SET_DRONE                = 'Ctrl+Alt+F17'
    CAM_SMART_VIEW_HOLD          = 'Ctrl+Alt+F18'
    CAM_CENTER_TRAFFIC_VIEW      = 'Ctrl+Alt+F19'
    CAM_SET_FLYBY                = 'Ctrl+Alt+F20'
    CAM_NEXT_CINEMATIC           = 'Ctrl+Alt+F21'
    CAM_CENTER_TRAFFIC_TRACK     = 'Ctrl+Alt+F22'
    CAM_SET_OVERVIEW             = 'Ctrl+Alt+F23'
    CAM_BINOCULARS               = 'Ctrl+Alt+F24'
    CAM_CONTROL_PROFILE_SLOW     = 'Ctrl+Alt+1'
    CAM_CONTROL_PROFILE_NORMAL   = 'Ctrl+Alt+2'
    CAM_CONTROL_PROFILE_FAST     = 'Ctrl+Alt+3'
    CAM_ROLL_L                   = 'Ctrl+Alt+4'
    CAM_DRAG_TOGGLE              = 'Ctrl+Alt+5'
    CAM_ROLL_R                   = 'Ctrl+Alt+6'
    CAM_RESET_ZOOM               = 'Ctrl+Alt+7'
    CAM_RESET_ORIENT             = 'Ctrl+Alt+8'
    CAM_TOGGLE_DOF               = 'Ctrl+Alt+9'
    CAM_HEAD_TRACKING_TOGGLE     = 'Ctrl+Alt+0'
    CAM_BINOCULARS_HOLD          = 'Ctrl+Alt+Z'
    CAM_TOGGLE_DOF_AUTOFOCUS     = 'Ctrl+Alt+X'
    CAM_TOGGLE_NVG               = 'Ctrl+Alt+C'
    CAM_EXPOSURE_LESS            = 'Ctrl+Alt+V'
    CAM_NVG_INTENSITY_LESS       = 'Ctrl+Alt+B'
    CAM_EXPOSURE_MORE            = 'Ctrl+Alt+N'
    CAM_NVG_INTENSITY_MORE       = 'Ctrl+Alt+M'
}
function Get-Combo([string]$cmd) {
    if ($Existing.ContainsKey($cmd)) { return $Existing[$cmd] }
    if ($NewKeys.Contains($cmd)) { return $NewKeys[$cmd] }
    throw "No key combo defined for $cmd (add it to `$NewKeys)"
}

# ---------------------------------------------------------------- layout
# cat: mode | nav | world | peek | smart | move | reset | fx | speed   (colours below)
function K($c, $r, $cmd, $label, $icon, $cat) { @{ c = $c; r = $r; cmd = $cmd; label = $label; icon = $icon; cat = $cat } }
function T($c, $page, $label, $icon) { @{ c = $c; r = 0; tab = $page; label = $label; icon = $icon; cat = "tab$page" } }

$TabBar = @(
    (T 0 1 'VIEWS' 'eye'), (T 1 2 'WORLD' 'globe'), (T 2 3 'FLY CAM' 'drone'), (T 3 4 'FX' 'sun')
)
$Global = @(     # same four keys on every page
    (K 4 0 'CAM_PREV_VIEW' "PREV`nVIEW" 'prev' 'nav')
    (K 5 0 'CAM_NEXT_VIEW' "NEXT`nVIEW" 'next' 'nav')
    (K 6 0 'CAM_TOGGLE_IN_OUT' "IN / OUT" 'toggle' 'mode')
    (K 7 0 'CAM_RESET' "RESET`nCAMERA" 'reset' 'reset')
)
$Pages = @(
  @{ name = 'Views'; keys = @(
      (K 0 1 'CAM_SET_ONBOARD' "COCKPIT" 'cockpit' 'mode')
      (K 1 1 'CAM_SET_OUTSIDE' "EXTERNAL" 'plane' 'mode')
      (K 2 1 'CAM_SET_WORLD' "WORLD" 'globe' 'world')
      (K 3 1 'CAM_SET_CINEMATIC' "CINEMATIC" 'clapper' 'smart')
      (K 4 1 'CAM_SET_DRONE' "DRONE" 'drone' 'world')
      (K 5 1 'CAM_SET_FLYBY' "FLYBY" 'flyby' 'world')
      (K 6 1 'CAM_SET_OVERVIEW' "OVERVIEW" 'overview' 'world')
      (K 7 1 'CAM_SMART_VIEW' "SMART`nVIEW" 'star' 'smart')
      (K 0 2 'CAM_PREV_GROUP' "PREV`nGROUP" 'prev2' 'nav')
      (K 1 2 'CAM_NEXT_GROUP' "NEXT`nGROUP" 'next2' 'nav')
      (K 2 2 'CAM_NEXT_CINEMATIC' "NEXT`nCINEMA" 'clappernext' 'smart')
      (K 3 2 'CAM_SMART_VIEW_HOLD' "SMART`nHOLD" 'starhold' 'smart')
      (K 4 2 'CAM_FLASHLIGHT_TOGGLE' "FLASH-`nLIGHT" 'flashlight' 'fx')
      (K 5 2 'CAM_BINOCULARS' "BINO-`nCULARS" 'binoculars' 'fx')
      (K 0 3 'CAM_QUICK_VIEW_LEFT' "PEEK`nLEFT" 'eyeL' 'peek')
      (K 1 3 'CAM_QUICK_VIEW_RIGHT' "PEEK`nRIGHT" 'eyeR' 'peek')
      (K 2 3 'CAM_QUICK_VIEW_UP' "PEEK`nUP" 'eyeU' 'peek')
      (K 3 3 'CAM_QUICK_VIEW_DOWN' "PEEK`nDOWN" 'eyeD' 'peek')
      (K 4 3 'CAM_QUICK_VIEW_BEHIND' "PEEK`nBACK" 'eyeB' 'peek')
  ) },
  @{ name = 'World'; keys = @(
      (K 0 1 'CAM_NEAR_TOWER' "TOWER" 'tower' 'world')
      (K 1 1 'CAM_NEAR_RUNWAY' "RUNWAY" 'runway' 'world')
      (K 2 1 'CAM_NEAR_PARKING' "PARKING" 'parking' 'world')
      (K 3 1 'CAM_NEAR_SPOTTING' "SPOTTING" 'camera' 'world')
      (K 4 1 'CAM_NEAR_TRAFFIC' "TRAFFIC" 'traffic' 'world')
      (K 5 1 'CAM_CENTER_TRAFFIC_VIEW' "TRAFFIC`nVIEW" 'trafficview' 'world')
      (K 6 1 'CAM_CENTER_TRAFFIC_TRACK' "TRAFFIC`nTRACK" 'traffictrack' 'world')
      (K 0 2 'CAM_SET_DRONE' "DRONE" 'drone' 'world')
      (K 1 2 'CAM_SET_FLYBY' "FLYBY" 'flyby' 'world')
      (K 2 2 'CAM_SET_OVERVIEW' "OVERVIEW" 'overview' 'world')
      (K 3 2 'CAM_SET_WORLD' "WORLD" 'globe' 'world')
      (K 4 2 'CAM_SET_CINEMATIC' "CINEMATIC" 'clapper' 'smart')
      (K 5 2 'CAM_NEXT_CINEMATIC' "NEXT`nCINEMA" 'clappernext' 'smart')
      (K 0 3 'CAM_ZOOM_IN' "ZOOM`nIN" 'zoomin' 'fx')
      (K 1 3 'CAM_ZOOM_OUT' "ZOOM`nOUT" 'zoomout' 'fx')
      (K 2 3 'CAM_RESET_ZOOM' "RESET`nZOOM" 'zoomreset' 'reset')
      (K 3 3 'CAM_QUICK_VIEW_LEFT' "PEEK`nLEFT" 'eyeL' 'peek')
      (K 4 3 'CAM_QUICK_VIEW_RIGHT' "PEEK`nRIGHT" 'eyeR' 'peek')
      (K 5 3 'CAM_QUICK_VIEW_UP' "PEEK`nUP" 'eyeU' 'peek')
      (K 6 3 'CAM_QUICK_VIEW_DOWN' "PEEK`nDOWN" 'eyeD' 'peek')
      (K 7 3 'CAM_QUICK_VIEW_BEHIND' "PEEK`nBACK" 'eyeB' 'peek')
  ) },
  @{ name = 'Fly cam'; keys = @(
      (K 0 1 'CAM_MOVE_D' "DOWN" 'mvlower' 'move')
      (K 1 1 'CAM_MOVE_F' "FORWARD" 'mvup' 'move')
      (K 2 1 'CAM_MOVE_U' "UP" 'mvlift' 'move')
      (K 0 2 'CAM_MOVE_L' "LEFT" 'mvleft' 'move')
      (K 1 2 'CAM_MOVE_B' "BACK" 'mvdown' 'move')
      (K 2 2 'CAM_MOVE_R' "RIGHT" 'mvright' 'move')
      (K 3 1 'CAM_ROLL_L' "ROLL`nLEFT" 'rotccw' 'peek')
      (K 4 1 'CAM_ROT_U' "LOOK`nUP" 'eyeU' 'peek')
      (K 5 1 'CAM_ROLL_R' "ROLL`nRIGHT" 'rotcw' 'peek')
      (K 3 2 'CAM_ROT_L' "LOOK`nLEFT" 'eyeL' 'peek')
      (K 4 2 'CAM_ROT_D' "LOOK`nDOWN" 'eyeD' 'peek')
      (K 5 2 'CAM_ROT_R' "LOOK`nRIGHT" 'eyeR' 'peek')
      (K 6 1 'CAM_ZOOM_IN' "ZOOM`nIN" 'zoomin' 'fx')
      (K 7 1 'CAM_ZOOM_OUT' "ZOOM`nOUT" 'zoomout' 'fx')
      (K 6 2 'CAM_RESET_ZOOM' "RESET`nZOOM" 'zoomreset' 'reset')
      (K 7 2 'CAM_RESET_ORIENT' "RESET`nHORIZON" 'horizon' 'reset')
      (K 0 3 'CAM_CONTROL_PROFILE_SLOW' "SPEED`nSLOW" 'chev1' 'speed')
      (K 1 3 'CAM_CONTROL_PROFILE_NORMAL' "SPEED`nNORMAL" 'chev2' 'speed')
      (K 2 3 'CAM_CONTROL_PROFILE_FAST' "SPEED`nFAST" 'chev3' 'speed')
      (K 3 3 'CAM_BOOST_SET' "BOOST`n(HOLD)" 'bolt' 'speed')
      (K 4 3 'CAM_DRAG_TOGGLE' "DRAG`nMODE" 'drag' 'speed')
  ) },
  @{ name = 'FX'; keys = @(
      (K 0 1 'CAM_BINOCULARS' "BINO-`nCULARS" 'binoculars' 'fx')
      (K 1 1 'CAM_BINOCULARS_HOLD' "BINO`n(HOLD)" 'binoculars' 'fx')
      (K 2 1 'CAM_FLASHLIGHT_TOGGLE' "FLASH-`nLIGHT" 'flashlight' 'fx')
      (K 3 1 'CAM_TOGGLE_NVG' "NIGHT`nVISION" 'moon' 'fx')
      (K 4 1 'CAM_NVG_INTENSITY_LESS' "NVG`nLESS" 'moonminus' 'fx')
      (K 5 1 'CAM_NVG_INTENSITY_MORE' "NVG`nMORE" 'moonplus' 'fx')
      (K 0 2 'CAM_TOGGLE_DOF' "DEPTH OF`nFIELD" 'focus' 'fx')
      (K 1 2 'CAM_TOGGLE_DOF_AUTOFOCUS' "AUTO`nFOCUS" 'autofocus' 'fx')
      (K 2 2 'CAM_EXPOSURE_LESS' "EXPOSURE`nLESS" 'sunminus' 'fx')
      (K 3 2 'CAM_EXPOSURE_MORE' "EXPOSURE`nMORE" 'sunplus' 'fx')
      (K 4 2 'CAM_HEAD_TRACKING_TOGGLE' "HEAD`nTRACKING" 'head' 'fx')
  ) }
)

# ---------------------------------------------------------------- bridge (plugin) actions and the hybrid layout
$PluginId = 'com.chaseplanexl.deck'
$PluginName = 'ChasePlane Deck'
$PluginVersion = (Get-Content (Join-Path $Root 'VERSION') -Raw).Trim()      # one version for plugin, profiles and installer: edit the file VERSION
$ManifestFile = Join-Path $Root 'plugin\com.chaseplanexl.deck.sdPlugin\manifest.json'
$mt = [System.IO.File]::ReadAllText($ManifestFile)
$mt2 = (New-Object System.Text.RegularExpressions.Regex '("Version"\s*:\s*")[0-9.]+(")').Replace($mt, ('${1}' + $PluginVersion + '${2}'), 1)      # first match = the plugin's own version
if ($mt2 -ne $mt) { [System.IO.File]::WriteAllText($ManifestFile, $mt2, (New-Object System.Text.UTF8Encoding $false)) }
$BridgeActions = [ordered]@{
    'mode.cockpit'      = @{ name = 'Cockpit view';        label = 'COCKPIT';          icon = 'cockpit';     cat = 'mode' }
    'mode.external'     = @{ name = 'External view';       label = 'EXTERNAL';         icon = 'plane';       cat = 'mode' }
    'mode.world'        = @{ name = 'World view';          label = 'WORLD';            icon = 'globe';       cat = 'world' }
    'mode.toggle'       = @{ name = 'Inside / outside';    label = 'IN / OUT';         icon = 'toggle';      cat = 'mode' }
    'cinematic.toggle'  = @{ name = 'Cinematic';           label = 'CINEMATIC';        icon = 'clapper';     cat = 'smart' }
    'cinematic.next'    = @{ name = 'Next cinematic shot'; label = "NEXT`nCINEMA";     icon = 'clappernext'; cat = 'smart' }
    'flashlight.toggle' = @{ name = 'Flashlight';          label = "FLASH-`nLIGHT";    icon = 'flashlight';  cat = 'fx' }
    'near.tower'        = @{ name = 'Nearest tower';       label = 'TOWER';            icon = 'tower';       cat = 'world' }
    'near.runway'       = @{ name = 'Nearest runway';      label = 'RUNWAY';           icon = 'runway';      cat = 'world' }
    'near.parking'      = @{ name = 'Nearest parking';     label = 'PARKING';          icon = 'parking';     cat = 'world' }
    'near.spotting'     = @{ name = 'Nearest spotting';    label = 'SPOTTING';         icon = 'camera';      cat = 'world' }
    'world.drone'       = @{ name = 'Drone camera';        label = 'DRONE';            icon = 'drone';       cat = 'world' }
    'world.flyby'       = @{ name = 'Flyby camera';        label = 'FLYBY';            icon = 'flyby';       cat = 'world' }
    'world.traffic'     = @{ name = 'Traffic camera';      label = 'TRAFFIC';          icon = 'traffic';     cat = 'world' }
}
# ChasePlane commands that the Bridge can run itself (plugin: set_control_profile); the plugin profiles need no ChasePlane key for them
$BridgeNative = @('CAM_CONTROL_PROFILE_SLOW', 'CAM_CONTROL_PROFILE_NORMAL', 'CAM_CONTROL_PROFILE_FAST')
# command keys that get a second, lit face because the Bridge reports their state (control_profile, head_tracking_enabled in cam_mode_set)
$BridgeLit = @('CAM_CONTROL_PROFILE_SLOW', 'CAM_CONTROL_PROFILE_NORMAL', 'CAM_CONTROL_PROFILE_FAST', 'CAM_HEAD_TRACKING_TOGGLE')
function B($c, $r, $id) { $a = $BridgeActions[$id]; @{ c = $c; r = $r; bridge = $id; label = $a.label; icon = $a.icon; cat = $a.cat } }
function V($c, $r, $slot) { @{ c = $c; r = $r; slot = $slot; label = ''; icon = 'none'; cat = 'mode' } }
function S($c, $r) { @{ c = $c; r = $r; status = $true; label = ''; icon = 'status'; cat = 'reset' } }
$GlobalBridge = @(     # same four keys on every page of the hybrid profile
    (K 4 0 'CAM_PREV_VIEW' "PREV`nVIEW" 'prev' 'nav')
    (K 5 0 'CAM_NEXT_VIEW' "NEXT`nVIEW" 'next' 'nav')
    (B 6 0 'mode.toggle')
    (K 7 0 'CAM_RESET' "RESET`nCAMERA" 'reset' 'reset')
)
$PagesBridge = @(
  @{ name = 'Views'; keys = @(
      (B 0 1 'mode.cockpit'), (B 1 1 'mode.external'), (B 2 1 'mode.world'), (B 3 1 'cinematic.toggle'), (B 4 1 'cinematic.next'), (B 5 1 'flashlight.toggle'), (S 7 1)
      (V 0 2 1), (V 1 2 2), (V 2 2 3), (V 3 2 4), (V 4 2 5), (V 5 2 6), (V 6 2 7), (V 7 2 8)
      (V 0 3 9), (V 1 3 10), (V 2 3 11), (V 3 3 12), (V 4 3 13), (V 5 3 14), (V 6 3 15), (V 7 3 16)
  ) },
  @{ name = 'World'; keys = @(
      (B 0 1 'near.tower'), (B 1 1 'near.runway'), (B 2 1 'near.parking'), (B 3 1 'near.spotting'), (B 4 1 'world.drone'), (B 5 1 'world.flyby'), (B 6 1 'world.traffic'), (B 7 1 'cinematic.toggle')
      (K 0 2 'CAM_ZOOM_IN' "ZOOM`nIN" 'zoomin' 'fx')
      (K 1 2 'CAM_ZOOM_OUT' "ZOOM`nOUT" 'zoomout' 'fx')
      (K 2 2 'CAM_RESET_ZOOM' "RESET`nZOOM" 'zoomreset' 'reset')
      (K 3 2 'CAM_QUICK_VIEW_LEFT' "PEEK`nLEFT" 'eyeL' 'peek')
      (K 4 2 'CAM_QUICK_VIEW_RIGHT' "PEEK`nRIGHT" 'eyeR' 'peek')
      (K 5 2 'CAM_QUICK_VIEW_UP' "PEEK`nUP" 'eyeU' 'peek')
      (K 6 2 'CAM_QUICK_VIEW_DOWN' "PEEK`nDOWN" 'eyeD' 'peek')
      (K 7 2 'CAM_QUICK_VIEW_BEHIND' "PEEK`nBACK" 'eyeB' 'peek')
      (B 0 3 'cinematic.next'), (B 1 3 'flashlight.toggle')
  ) },
  $Pages[2],
  @{ name = 'FX'; keys = @(
      (B 0 1 'flashlight.toggle'), (B 1 1 'cinematic.toggle'), (B 2 1 'cinematic.next')
      (K 4 1 'CAM_TOGGLE_NVG' "NIGHT`nVISION" 'moon' 'fx')
      (K 5 1 'CAM_NVG_INTENSITY_LESS' "NVG`nLESS" 'moonminus' 'fx')
      (K 6 1 'CAM_NVG_INTENSITY_MORE' "NVG`nMORE" 'moonplus' 'fx')
      (K 0 2 'CAM_BINOCULARS' "BINO-`nCULARS" 'binoculars' 'fx')
      (K 1 2 'CAM_BINOCULARS_HOLD' "BINO`n(HOLD)" 'binoculars' 'fx')
      (K 2 2 'CAM_TOGGLE_DOF' "DEPTH OF`nFIELD" 'focus' 'fx')
      (K 3 2 'CAM_TOGGLE_DOF_AUTOFOCUS' "AUTO`nFOCUS" 'autofocus' 'fx')
      (K 4 2 'CAM_EXPOSURE_LESS' "EXPOSURE`nLESS" 'sunminus' 'fx')
      (K 5 2 'CAM_EXPOSURE_MORE' "EXPOSURE`nMORE" 'sunplus' 'fx')
      (K 6 2 'CAM_HEAD_TRACKING_TOGGLE' "HEAD`nTRACKING" 'head' 'fx')
  ) }
)

# ---------------------------------------------------------------- style
# cat -> background top, background bottom, accent (icon colour)
$Style = @{
    mode  = @('#1B3358', '#0E1A2E', '#58AEFF'); nav   = @('#2A2A58', '#171734', '#9C99FF')
    world = @('#4F2D12', '#2B1708', '#FFA94F'); peek  = @('#3F2460', '#221239', '#CB94FF')
    smart = @('#5A1C3E', '#33102A', '#FF66B3'); move  = @('#0F4343', '#082727', '#40E0D6')
    reset = @('#571E1E', '#2F1010', '#FF7070'); fx    = @('#18432A', '#0C2415', '#5CE880')
    speed = @('#4E3D08', '#2B2204', '#FFD640'); tab   = @('#272B34', '#171A20', '#AAB2C0')
}
$TabAccent = @{ tab1 = '#58AEFF'; tab2 = '#FFA94F'; tab3 = '#40E0D6'; tab4 = '#5CE880'; tabL = '#CB94FF'; tabC = '#FF66B3' }

function Col([string]$hex, [int]$a = 255) { $c = [System.Drawing.ColorTranslator]::FromHtml($hex); [System.Drawing.Color]::FromArgb($a, $c.R, $c.G, $c.B) }
function Mix([string]$hex1, [string]$hex2, [double]$t) {
    $a = [System.Drawing.ColorTranslator]::FromHtml($hex1); $b = [System.Drawing.ColorTranslator]::FromHtml($hex2)
    [System.Drawing.Color]::FromArgb(255, [int]($a.R + ($b.R - $a.R) * $t), [int]($a.G + ($b.G - $a.G) * $t), [int]($a.B + ($b.B - $a.B) * $t))
}

# ---------------------------------------------------------------- icons (local coordinates -1..1, scaled by $script:h)
function P([double]$x, [double]$y) { [System.Drawing.PointF]::new([single]($x * $script:h), [single]($y * $script:h)) }
function Poly($pts) { $script:g.FillPolygon($script:fill, [System.Drawing.PointF[]]$pts) }
function L([double]$x1, [double]$y1, [double]$x2, [double]$y2) { $a = P $x1 $y1; $b = P $x2 $y2; $script:g.DrawLine($script:pen, $a, $b) }
function EO([double]$x, [double]$y, [double]$rx, [double]$ry) { $script:g.DrawEllipse($script:pen, [single](($x - $rx) * $script:h), [single](($y - $ry) * $script:h), [single](2 * $rx * $script:h), [single](2 * $ry * $script:h)) }
function EF([double]$x, [double]$y, [double]$rx, [double]$ry) { $script:g.FillEllipse($script:fill, [single](($x - $rx) * $script:h), [single](($y - $ry) * $script:h), [single](2 * $rx * $script:h), [single](2 * $ry * $script:h)) }
function RO([double]$x1, [double]$y1, [double]$x2, [double]$y2) { $script:g.DrawRectangle($script:pen, [single]($x1 * $script:h), [single]($y1 * $script:h), [single](($x2 - $x1) * $script:h), [single](($y2 - $y1) * $script:h)) }
function RF([double]$x1, [double]$y1, [double]$x2, [double]$y2) { $script:g.FillRectangle($script:fill, [single]($x1 * $script:h), [single]($y1 * $script:h), [single](($x2 - $x1) * $script:h), [single](($y2 - $y1) * $script:h)) }
function ArcO([double]$x, [double]$y, [double]$r, [double]$start, [double]$sweep) { $script:g.DrawArc($script:pen, [single](($x - $r) * $script:h), [single](($y - $r) * $script:h), [single](2 * $r * $script:h), [single](2 * $r * $script:h), [single]$start, [single]$sweep) }
function Head([double]$tx, [double]$ty, [double]$dx, [double]$dy, [double]$len, [double]$wid) {
    $n = [math]::Sqrt($dx * $dx + $dy * $dy); $dx /= $n; $dy /= $n
    $bx = $tx - $dx * $len; $by = $ty - $dy * $len; $px = -$dy; $py = $dx
    Poly @((P $tx $ty), (P ($bx + $px * $wid) ($by + $py * $wid)), (P ($bx - $px * $wid) ($by - $py * $wid)))
}
function Txt([string]$text, [double]$x, [double]$y, [double]$size) {
    $f = New-Object System.Drawing.Font('Segoe UI', [single]($size * $script:h), [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
    $sf = New-Object System.Drawing.StringFormat; $sf.Alignment = 'Center'; $sf.LineAlignment = 'Center'
    $pt = P $x $y; $script:g.DrawString($text, $f, $script:fill, $pt, $sf); $f.Dispose()
}
function Sub-Icon([double]$ox, [double]$oy, [double]$scale, [double]$angle, [scriptblock]$body) {
    $st = $script:g.Save()
    $script:g.TranslateTransform([single]($ox * $script:h), [single]($oy * $script:h))
    $script:g.RotateTransform([single]$angle)
    $script:g.ScaleTransform([single]$scale, [single]$scale)
    & $body
    $script:g.Restore($st)
}
function Do-Plane {
    EF 0 0 0.11 0.92
    Poly @((P -0.1 -0.15), (P -0.95 0.38), (P -0.95 0.52), (P -0.1 0.22))
    Poly @((P 0.1 -0.15), (P 0.95 0.38), (P 0.95 0.52), (P 0.1 0.22))
    Poly @((P -0.1 0.66), (P -0.42 0.9), (P -0.42 0.98), (P -0.1 0.84))
    Poly @((P 0.1 0.66), (P 0.42 0.9), (P 0.42 0.98), (P 0.1 0.84))
}
function Do-Eye {
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddBezier((P -0.95 0), (P -0.4 -0.7), (P 0.4 -0.7), (P 0.95 0))
    $path.AddBezier((P 0.95 0), (P 0.4 0.7), (P -0.4 0.7), (P -0.95 0))
    $script:g.DrawPath($script:pen, $path); $path.Dispose()
    EF 0 0 0.3 0.3
}
function Do-ArcArrow([bool]$ccw, [double]$r) {
    $st = $script:g.Save()
    if ($ccw) { $script:g.ScaleTransform(-1, 1) }
    ArcO 0 0 $r -70 290
    $a = 220 * [math]::PI / 180
    $ex = $r * [math]::Cos($a); $ey = $r * [math]::Sin($a)
    Head ($ex - [math]::Sin($a) * -0.05) ($ey + [math]::Cos($a) * -0.05) (-[math]::Sin($a)) ([math]::Cos($a)) 0.42 0.3
    $script:g.Restore($st)
}
function Do-Brackets([double]$s, [double]$len) {
    foreach ($sx in -1, 1) { foreach ($sy in -1, 1) {
        L ($sx * $s) ($sy * $s) ($sx * $s) ($sy * ($s - $len)); L ($sx * $s) ($sy * $s) ($sx * ($s - $len)) ($sy * $s)
    } }
}
function Do-Sun {
    EF 0 0 0.32 0.32
    for ($i = 0; $i -lt 8; $i++) { $a = $i * [math]::PI / 4; L (0.52 * [math]::Cos($a)) (0.52 * [math]::Sin($a)) (0.82 * [math]::Cos($a)) (0.82 * [math]::Sin($a)) }
}
function Do-Moon {
    $p1 = New-Object System.Drawing.Drawing2D.GraphicsPath; $p1.AddEllipse([single](-0.7 * $script:h), [single](-0.7 * $script:h), [single](1.4 * $script:h), [single](1.4 * $script:h))
    $p2 = New-Object System.Drawing.Drawing2D.GraphicsPath; $p2.AddEllipse([single](-0.3 * $script:h), [single](-0.9 * $script:h), [single](1.3 * $script:h), [single](1.3 * $script:h))
    $reg = New-Object System.Drawing.Region($p1); $reg.Exclude($p2); $script:g.FillRegion($script:fill, $reg)
    Poly @((P 0.45 0.3), (P 0.52 0.5), (P 0.72 0.55), (P 0.52 0.62), (P 0.45 0.82), (P 0.38 0.62), (P 0.18 0.55), (P 0.38 0.5))
}
function Do-Badge([string]$sign) {
    EF 0.62 0.62 0.36 0.36
    $sv = $script:pen.Color; $script:pen.Color = [System.Drawing.Color]::FromArgb(255, 20, 20, 20)
    $w = $script:pen.Width; $script:pen.Width = $w * 0.7
    L 0.46 0.62 0.78 0.62
    if ($sign -eq '+') { L 0.62 0.46 0.62 0.78 }
    $script:pen.Color = $sv; $script:pen.Width = $w
}
function Do-Clapper {
    RO -0.85 -0.1 0.85 0.8
    Poly @((P -0.9 -0.18), (P -0.9 -0.58), (P 0.9 -0.9), (P 0.9 -0.5))
    Poly @((P -0.15 0.12), (P -0.15 0.6), (P 0.3 0.36))
}

function Draw-Icon([string]$name) {
    switch ($name) {
        'toggle'   { L -0.8 -0.3 0.35 -0.3; Head 0.9 -0.3 1 0 0.5 0.35; L 0.8 0.3 -0.35 0.3; Head -0.9 0.3 -1 0 0.5 0.35 }
        'cockpit'  { $pts = @((P -0.9 0.3), (P -0.62 -0.7), (P 0.62 -0.7), (P 0.9 0.3)); $script:g.DrawPolygon($script:pen, [System.Drawing.PointF[]]$pts)
                     L 0 -0.7 0 0.3; L -0.9 0.3 0.9 0.3; RF -0.9 0.42 0.9 0.82; EF -0.45 0.62 0.14 0.14; EF 0.45 0.62 0.14 0.14 }
        'plane'    { Do-Plane }
        'globe'    { EO 0 0 0.85 0.85; EO 0 0 0.4 0.85; L -0.85 0 0.85 0; L -0.7 -0.42 0.7 -0.42; L -0.7 0.42 0.7 0.42 }
        'clapper'  { Do-Clapper }
        'clappernext' { Sub-Icon -0.15 0 0.78 0 { Do-Clapper }; Head 0.98 0.05 1 0 0.42 0.3; Head 0.66 0.05 1 0 0.42 0.3 }
        'drone'    { EF 0 0 0.2 0.2; foreach ($s in @(@(-1,-1), @(1,-1), @(-1,1), @(1,1))) { L 0 0 ($s[0]*0.55) ($s[1]*0.55); EO ($s[0]*0.62) ($s[1]*0.62) 0.3 0.3 } }
        'flyby'    { Sub-Icon 0.3 -0.1 0.62 40 { Do-Plane }; L -0.9 0.5 -0.35 0.5; L -0.9 0.1 -0.5 0.1; L -0.7 0.9 -0.15 0.9 }
        'overview' { EO 0 0 0.55 0.55; L -0.95 0 -0.35 0; L 0.35 0 0.95 0; L 0 -0.95 0 -0.35; L 0 0.35 0 0.95; EF 0 0 0.12 0.12 }
        'prev'     { RF -0.85 -0.7 -0.65 0.7; Poly @((P 0.8 -0.72), (P -0.4 0), (P 0.8 0.72)) }
        'next'     { RF 0.65 -0.7 0.85 0.7; Poly @((P -0.8 -0.72), (P 0.4 0), (P -0.8 0.72)) }
        'prev2'    { Poly @((P 0.05 -0.7), (P -0.85 0), (P 0.05 0.7)); Poly @((P 0.9 -0.7), (P 0.0 0), (P 0.9 0.7)) }
        'next2'    { Poly @((P -0.05 -0.7), (P 0.85 0), (P -0.05 0.7)); Poly @((P -0.9 -0.7), (P 0.0 0), (P -0.9 0.7)) }
        'star'     { Poly @((P 0 -0.95), (P 0.22 -0.22), (P 0.95 0), (P 0.22 0.22), (P 0 0.95), (P -0.22 0.22), (P -0.95 0), (P -0.22 -0.22)) }
        'starhold' { Sub-Icon 0 0 0.72 0 { Draw-Icon 'star' }; EO 0 0 0.9 0.9 }
        'reset'    { Do-ArcArrow $false 0.62; EF 0 0 0.1 0.1 }
        'tower'    { Poly @((P -0.16 0.9), (P 0.16 0.9), (P 0.1 -0.1), (P -0.1 -0.1)); Poly @((P -0.55 -0.1), (P 0.55 -0.1), (P 0.7 -0.58), (P -0.7 -0.58)); L 0 -0.58 0 -0.95; RF -0.5 0.84 0.5 0.92 }
        'runway'   { $pts = @((P -0.22 -0.9), (P 0.22 -0.9), (P 0.9 0.9), (P -0.9 0.9)); $script:g.DrawPolygon($script:pen, [System.Drawing.PointF[]]$pts)
                     RF -0.04 -0.65 0.04 -0.45; RF -0.06 -0.25 0.06 0.05; RF -0.09 0.3 0.09 0.7 }
        'parking'  { RO -0.8 -0.8 0.8 0.8; Txt 'P' 0 0.02 1.35 }
        'camera'   { RO -0.85 -0.4 0.85 0.7; RF -0.3 -0.72 0.3 -0.4; EO 0 0.15 0.36 0.36 }
        'traffic'  { Sub-Icon 0 0 0.62 0 { Do-Plane }; EO 0 0 0.92 0.92 }
        'trafficview'  { Sub-Icon 0 0 0.5 0 { Do-Plane }; Do-Brackets 0.88 0.38 }
        'traffictrack' { Sub-Icon 0 0 0.5 -25 { Do-Plane }; EO 0 0 0.85 0.85; L -0.98 0 -0.7 0; L 0.7 0 0.98 0; L 0 -0.98 0 -0.7; L 0 0.7 0 0.98 }
        'binoculars' { EO -0.45 0.2 0.38 0.38; EO 0.45 0.2 0.38 0.38; RF -0.12 -0.05 0.12 0.35; RF -0.75 -0.5 -0.2 -0.2; RF 0.2 -0.5 0.75 -0.2 }
        'flashlight' { Poly @((P -0.32 -0.5), (P 0.32 -0.5), (P 0.2 -0.15), (P -0.2 -0.15)); RF -0.2 -0.15 0.2 0.85
                     L -0.5 -0.7 -0.7 -0.92; L 0 -0.78 0 -1.0; L 0.5 -0.7 0.7 -0.92 }
        'none'     { }
        'status'   { EO 0 0 0.55 0.55; EF 0 0 0.22 0.22; L -0.95 0 -0.75 0; L 0.75 0 0.95 0; L 0 -0.95 0 -0.75; L 0 0.75 0 0.95 }
        'eye'      { Do-Eye }
        'eyeL'     { Sub-Icon 0.28 0 0.7 0 { Do-Eye }; L -0.1 0 -0.8 0; Head -0.98 0 -1 0 0.42 0.32 }
        'eyeR'     { Sub-Icon -0.28 0 0.7 0 { Do-Eye }; L 0.1 0 0.8 0; Head 0.98 0 1 0 0.42 0.32 }
        'eyeU'     { Sub-Icon 0 0.4 0.7 0 { Do-Eye }; L 0 0 0 -0.6; Head 0 -0.95 0 -1 0.42 0.32 }
        'eyeD'     { Sub-Icon 0 -0.4 0.7 0 { Do-Eye }; L 0 0 0 0.6; Head 0 0.95 0 1 0.42 0.32 }
        'eyeB'     { Sub-Icon 0 0 0.5 0 { Do-Eye }; Do-ArcArrow $false 0.85 }
        'rotcw'    { Do-ArcArrow $false 0.7; Sub-Icon 0 0 0.35 0 { Do-Plane } }
        'rotccw'   { Do-ArcArrow $true 0.7; Sub-Icon 0 0 0.35 0 { Do-Plane } }
        'mvup'     { Poly @((P 0 -0.95), (P 0.7 -0.1), (P 0.3 -0.1), (P 0.3 0.85), (P -0.3 0.85), (P -0.3 -0.1), (P -0.7 -0.1)) }
        'mvdown'   { Poly @((P 0 0.95), (P 0.7 0.1), (P 0.3 0.1), (P 0.3 -0.85), (P -0.3 -0.85), (P -0.3 0.1), (P -0.7 0.1)) }
        'mvleft'   { Poly @((P -0.95 0), (P -0.1 -0.7), (P -0.1 -0.3), (P 0.85 -0.3), (P 0.85 0.3), (P -0.1 0.3), (P -0.1 0.7)) }
        'mvright'  { Poly @((P 0.95 0), (P 0.1 -0.7), (P 0.1 -0.3), (P -0.85 -0.3), (P -0.85 0.3), (P 0.1 0.3), (P 0.1 0.7)) }
        'mvlower'  { RF -0.7 0.8 0.7 0.95; Poly @((P 0 0.65), (P 0.62 -0.05), (P 0.26 -0.05), (P 0.26 -0.85), (P -0.26 -0.85), (P -0.26 -0.05), (P -0.62 -0.05)) }
        'mvlift'   { RF -0.7 -0.95 0.7 -0.8; Poly @((P 0 -0.65), (P 0.62 0.05), (P 0.26 0.05), (P 0.26 0.85), (P -0.26 0.85), (P -0.26 0.05), (P -0.62 0.05)) }
        'zoomin'   { EO -0.15 -0.15 0.55 0.55; L 0.25 0.25 0.9 0.9; L -0.15 -0.4 -0.15 0.1; L -0.4 -0.15 0.1 -0.15 }
        'zoomout'  { EO -0.15 -0.15 0.55 0.55; L 0.25 0.25 0.9 0.9; L -0.4 -0.15 0.1 -0.15 }
        'zoomreset' { EO -0.15 -0.15 0.55 0.55; L 0.25 0.25 0.9 0.9; Txt '1' -0.15 -0.13 0.6 }
        'horizon'  { L -0.9 0.1 -0.3 0.1; L 0.3 0.1 0.9 0.1; ArcO 0 0.1 0.3 180 180; L 0 -0.3 0 -0.8; L -0.5 -0.45 -0.35 -0.55; L 0.5 -0.45 0.35 -0.55 }
        'chev1'    { L -0.2 -0.6 0.3 0 ; L 0.3 0 -0.2 0.6 }
        'chev2'    { L -0.45 -0.6 0.05 0; L 0.05 0 -0.45 0.6; L 0.1 -0.6 0.6 0; L 0.6 0 0.1 0.6 }
        'chev3'    { L -0.65 -0.6 -0.25 0; L -0.25 0 -0.65 0.6; L -0.2 -0.6 0.2 0; L 0.2 0 -0.2 0.6; L 0.25 -0.6 0.65 0; L 0.65 0 0.25 0.6 }
        'bolt'     { Poly @((P 0.12 -0.95), (P -0.55 0.1), (P -0.05 0.1), (P -0.15 0.95), (P 0.55 -0.15), (P 0.05 -0.15)) }
        'drag'     { L -0.75 0 0.75 0; L 0 -0.75 0 0.75; Head -0.98 0 -1 0 0.38 0.28; Head 0.98 0 1 0 0.38 0.28; Head 0 -0.98 0 -1 0.38 0.28; Head 0 0.98 0 1 0.38 0.28 }
        'moon'     { Do-Moon }
        'moonminus' { Sub-Icon -0.1 -0.1 0.8 0 { Do-Moon }; Do-Badge '-' }
        'moonplus' { Sub-Icon -0.1 -0.1 0.8 0 { Do-Moon }; Do-Badge '+' }
        'focus'    { Do-Brackets 0.85 0.38; EO 0 0 0.3 0.3; EO 0 0 0.12 0.12 }
        'autofocus' { Do-Brackets 0.85 0.38; Txt 'AF' 0 0.02 0.62 }
        'sun'      { Do-Sun }
        'sunminus' { Sub-Icon -0.1 -0.1 0.8 0 { Do-Sun }; Do-Badge '-' }
        'sunplus'  { Sub-Icon -0.1 -0.1 0.8 0 { Do-Sun }; Do-Badge '+' }
        'head'     { EF 0 -0.45 0.3 0.3; $script:g.FillPie($script:fill, [single](-0.62 * $script:h), [single](0.05 * $script:h), [single](1.24 * $script:h), [single](1.5 * $script:h), [single]180, [single]180)
                     ArcO 0 -0.45 0.62 140 -100 ; ArcO 0 -0.45 0.62 -40 -100 }
        default    { Txt '?' 0 0 1.2 }
    }
}

function New-KeyBitmap([string]$icon, [string]$label, [string]$cat, [bool]$active, [double]$iconY = 49, [double]$iconH = 31) {
    $bmp = New-Object System.Drawing.Bitmap 144, 144, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp); $script:g = $g
    $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'AntiAliasGridFit'; $g.PixelOffsetMode = 'HighQuality'
    $isTab = $cat -like 'tab?'
    if ($isTab) {
        $acc = $TabAccent[$cat]
        if ($active) { $top = Mix $acc '#000000' 0.18; $bot = Mix $acc '#000000' 0.5; $iconCol = [System.Drawing.Color]::White; $stripe = [System.Drawing.Color]::White }
        else { $s = $Style['tab']; $top = Col $s[0]; $bot = Col $s[1]; $iconCol = Col $acc; $stripe = Col $acc }
    } else {
        $s = $Style[$cat]
        if ($active) { $acc = $s[2]; $top = Mix $acc '#000000' 0.18; $bot = Mix $acc '#000000' 0.5; $iconCol = [System.Drawing.Color]::White; $stripe = [System.Drawing.Color]::White }   # lit key
        else { $top = Col $s[0]; $bot = Col $s[1]; $iconCol = Col $s[2]; $stripe = Col $s[2] }
    }
    # full-bleed background (the key bezel does the framing)
    $rect = New-Object System.Drawing.RectangleF 0, 0, 144, 144
    $br = New-Object System.Drawing.Drawing2D.LinearGradientBrush $rect, $top, $bot, 90
    $g.FillRectangle($br, $rect)
    # soft glow behind the icon
    $gp = New-Object System.Drawing.Drawing2D.GraphicsPath; $gp.AddEllipse(20, -6, 104, 104)
    $pg = New-Object System.Drawing.Drawing2D.PathGradientBrush $gp
    $pg.CenterColor = [System.Drawing.Color]::FromArgb(70, $iconCol.R, $iconCol.G, $iconCol.B)
    $pg.SurroundColors = [System.Drawing.Color[]]@([System.Drawing.Color]::FromArgb(0, $iconCol.R, $iconCol.G, $iconCol.B))
    $g.FillPath($pg, $gp)
    # accent stripe: top for normal keys and inactive tabs, bottom for the active tab
    $sb = New-Object System.Drawing.SolidBrush $stripe
    if ($active) { $g.FillRectangle($sb, 0, 134, 144, 10) } else { $g.FillRectangle($sb, 0, 0, 144, 7) }
    # icon
    $script:fill = New-Object System.Drawing.SolidBrush $iconCol
    $script:cx = 72; $script:cy = $iconY; $script:h = $iconH
    $script:pen = New-Object System.Drawing.Pen $iconCol, ([single](0.13 * $script:h))
    $script:pen.StartCap = 'Round'; $script:pen.EndCap = 'Round'; $script:pen.LineJoin = 'Round'
    $g.TranslateTransform($script:cx, $script:cy)
    Draw-Icon $icon
    $g.ResetTransform()
    # label
    $lines = $label -split "`n"
    $size = if ($lines.Count -gt 1) { 23.0 } else { 28.0 }
    do {
        $font = New-Object System.Drawing.Font('Segoe UI', [single]$size, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
        $wmax = ($lines | ForEach-Object { $g.MeasureString($_, $font).Width } | Measure-Object -Maximum).Maximum
        if ($wmax -gt 132 -and $size -gt 12) { $size -= 1; $font.Dispose(); $ok = $false } else { $ok = $true }
    } until ($ok)
    $sf = New-Object System.Drawing.StringFormat; $sf.Alignment = 'Center'; $sf.LineAlignment = 'Center'
    $lh = $size * 1.06
    $y0 = if ($lines.Count -eq 1) { 111 } else { 100 - 1 }
    $white = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
    for ($i = 0; $i -lt $lines.Count; $i++) { $g.DrawString($lines[$i], $font, $white, [single]72, [single]($y0 + $i * $lh), $sf) }
    $font.Dispose(); $g.Dispose(); $br.Dispose(); $pg.Dispose(); $gp.Dispose(); $sb.Dispose(); $white.Dispose(); $script:pen.Dispose(); $script:fill.Dispose()
    $bmp
}
function Get-PngBytes($bmp) { $ms = New-Object System.IO.MemoryStream; $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png); $ms.ToArray() }

# ---------------------------------------------------------------- png helpers
$Utf8 = New-Object System.Text.UTF8Encoding $false
function To-Json($o) { ($o | ConvertTo-Json -Depth 20 -Compress) }
function Get-PngBytes($bmp) { $ms = New-Object System.IO.MemoryStream; $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png); $ms.ToArray() }
$script:ImgCache = @{}
# PNG bytes for one key face (cached: the same face is used by profile pages and by plugin assets)
function Get-KeyPng([string]$icon, [string]$label, [string]$cat, [bool]$active = $false, [double]$iconY = 49, [double]$iconH = 31) {
    $k = "$icon|$label|$cat|$active|$iconY|$iconH"
    if (-not $script:ImgCache.ContainsKey($k)) {
        $b = New-KeyBitmap $icon $label $cat $active $iconY $iconH
        $script:ImgCache[$k] = Get-PngBytes $b; $b.Dispose()
    }
    $script:ImgCache[$k]
}
function Resize-Png([byte[]]$png, [int]$size) {
    $src = [System.Drawing.Image]::FromStream((New-Object System.IO.MemoryStream (, $png)))
    $dst = New-Object System.Drawing.Bitmap $size, $size, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($dst); $g.InterpolationMode = 'HighQualityBicubic'; $g.SmoothingMode = 'HighQuality'; $g.PixelOffsetMode = 'HighQuality'
    $g.DrawImage($src, 0, 0, $size, $size); $g.Dispose(); $src.Dispose()
    $out = Get-PngBytes $dst; $dst.Dispose(); $out
}
# view-slot tiles (the plugin puts the view name on top of these as a title)
$TileDefs = [ordered]@{
    view_m0 = @{ icon = 'cockpit'; cat = 'mode'; lit = $false }; view_m0_lit = @{ icon = 'cockpit'; cat = 'mode'; lit = $true }
    view_m1 = @{ icon = 'plane';   cat = 'fx';   lit = $false }; view_m1_lit = @{ icon = 'plane';   cat = 'fx';   lit = $true }
    view_m2 = @{ icon = 'globe';   cat = 'world'; lit = $false }; view_m2_lit = @{ icon = 'globe';  cat = 'world'; lit = $true }
}
function Get-TilePng([string]$name) {
    if ($TileDefs.Contains($name)) { $d = $TileDefs[$name]; return (Get-KeyPng $d.icon '' $d.cat $d.lit 38 22) }
    if ($name -eq 'view_empty')   { return (Get-KeyPng 'none' '' 'tab' $false 38 22) }
    if ($name -eq 'view_offline') { return (Get-KeyPng 'none' 'OFFLINE' 'tab' $false 38 22) }
    if ($name -eq 'status')       { return (Get-KeyPng 'status' '' 'reset' $false 38 22) }
    if ($name -eq 'status_lit')   { return (Get-KeyPng 'status' '' 'fx' $false 38 22) }
    throw "unknown tile $name"
}

# ---------------------------------------------------------------- profile builder
function Add-ZipDir($zip, [string]$name) { [void]$zip.CreateEntry($name) }
function Add-ZipBytes($zip, [string]$name, [byte[]]$bytes) {
    $e = $zip.CreateEntry($name, [System.IO.Compression.CompressionLevel]::Optimal); $s = $e.Open(); $s.Write($bytes, 0, $bytes.Length); $s.Close()
}
function New-State([string]$img, [bool]$title = $false, [string]$align = 'bottom', [int]$fontSize = 9) {
    [ordered]@{ FontFamily = ''; FontSize = $fontSize; FontStyle = ''; FontUnderline = $false; Image = $img
                OutlineThickness = 2; ShowTitle = $title; TitleAlignment = $align; TitleColor = '#ffffff' }
}

# Builds one .streamDeckProfile. Every page in $PageList already holds all of its keys (tab bar / navigation included).
# $Dev = device entry (model, extra controllers). $Format: 'v2' = legacy export (importable from file),
# 'v3' = current export (what Elgato and plugins ship; used for the profiles bundled in the plugin).
# Returns the list of hotkey commands used (with combo / first page / label).
$ExampleViews = @('Pilot', 'Copilot', 'Overhead', 'Pedestal', 'Left Panel', "Right`nPanel", 'Jumpseat', 'Cabin')   # preview sheets only
function Build-Profile($PageList, [string]$OutFile, [string]$Name, [string]$PreviewPrefix, $Dev, [string]$Format = 'v2', [bool]$IsBridge = $false) {
    $v3 = ($Format -eq 'v3')
    $profileUuid = (New-Uuid).ToUpper()
    $pageIds = @(); foreach ($p in $PageList) { $pageIds += (New-Uuid) }
    $defaultPage = New-Uuid
    $top = if ($v3) { "Profiles/$profileUuid.sdProfile" } else { "$profileUuid.sdProfile" }
    $extra = @(); foreach ($t in $Dev.extra) { $extra += [ordered]@{ Actions = [ordered]@{}; Type = $t } }
    if (Test-Path $OutFile) { Remove-Item $OutFile -Force }
    New-Item -ItemType Directory -Force -Path (Split-Path $OutFile -Parent) | Out-Null
    $fs = [System.IO.File]::Open($OutFile, [System.IO.FileMode]::CreateNew)
    $zip = New-Object System.IO.Compression.ZipArchive($fs, [System.IO.Compression.ZipArchiveMode]::Create)
    if ($v3) {
        $req = @('com.elgato.streamdeck.page'); if ($IsBridge) { $req += $PluginId } else { $req += 'com.elgato.streamdeck.system.hotkey' }
        $pkg = [ordered]@{ AppVersion = '7.4.2.22730'; DeviceModel = $Dev.model; DeviceSettings = $null; FormatVersion = 1
                           OSType = 'Windows'; OSVersion = '10.0.26200'; RequiredPlugins = $req }
        Add-ZipBytes $zip 'package.json' ($Utf8.GetBytes((To-Json $pkg)))
        Add-ZipDir $zip 'Profiles/'
    }
    Add-ZipDir $zip "$top/"; Add-ZipDir $zip "$top/Images/"; Add-ZipDir $zip "$top/Profiles/"
    $plugin = [ordered]@{ Name = $PluginName; UUID = $PluginId; Version = $PluginVersion }
    $hkPlugin = [ordered]@{ Name = 'Activate a Key Command'; UUID = 'com.elgato.streamdeck.system.hotkey'; Version = '1.0' }
    $used = New-Object System.Collections.Generic.List[object]
    $seen = @{}
    for ($pi = 0; $pi -lt $PageList.Count; $pi++) {
        $page = $PageList[$pi]
        $dir = if ($v3) { "$top/Profiles/$($pageIds[$pi].ToUpper())" } else { "$top/Profiles/$(Encode-Id $pageIds[$pi])" }
        Add-ZipDir $zip "$dir/"; Add-ZipDir $zip "$dir/Images/"
        $actions = [ordered]@{}; $faces = @{}; $titles = @{}
        foreach ($k in (@($page.keys) | Sort-Object { $_.c }, { $_.r })) {
            $pos = "$($k.c),$($k.r)"
            if ($k.c -ge $Dev.cols -or $k.r -ge $Dev.rows) { throw "Key $pos is outside the $($Dev.cols)x$($Dev.rows) grid of $($Dev.key) (page $($page.name))" }
            if ($actions.Contains($pos)) { throw "Two keys at $pos on $($Dev.key) page $($page.name)" }
            $isActive = [bool]($k.tab -and $k.tab -eq ($pi + 1))
            function Put-Image([byte[]]$png) { $n = (Encode-Id (New-Uuid)) + '.png'; Add-ZipBytes $zip "$dir/Images/$n" $png; "Images/$n" }
            if ($k.tab) {
                $png = Get-KeyPng $k.icon $k.label $k.cat $isActive; $faces[$pos] = $png
                $act = [ordered]@{ ActionID = (New-Uuid); LinkedTitle = $true; Name = 'Pages'
                                   Plugin = [ordered]@{ Name = 'Pages'; UUID = 'com.elgato.streamdeck.page'; Version = '1.0' }
                                   Resources = $null; Settings = [ordered]@{ PageIndex = [int]$k.tab - 1 + $GotoBase }; State = 0
                                   States = @((New-State (Put-Image $png) $false 'top' 12)); UUID = 'com.elgato.streamdeck.page.goto' }
            } elseif ($k.bridge) {
                $a = $BridgeActions[$k.bridge]
                $p0 = Get-KeyPng $k.icon $k.label $k.cat $false; $p1 = Get-KeyPng $k.icon $k.label $k.cat $true
                $faces[$pos] = if ($k.bridge -eq 'mode.cockpit') { $p1 } else { $p0 }      # preview shows the cockpit mode as active
                $act = [ordered]@{ ActionID = (New-Uuid); LinkedTitle = $true; Name = $a.name; Plugin = $plugin; Resources = $null
                                   Settings = [ordered]@{}; State = 0
                                   States = @((New-State (Put-Image $p0)), (New-State (Put-Image $p1))); UUID = "$PluginId.$($k.bridge)" }
            } elseif ($k.slot) {
                $png = Get-TilePng 'view_m0'
                $n = [int]$k.slot
                if ($n -le $ExampleViews.Count) { $faces[$pos] = (Get-TilePng $(if ($n -eq 1) { 'view_m0_lit' } else { 'view_m0' })); $titles[$pos] = $ExampleViews[$n - 1] }
                else { $faces[$pos] = (Get-TilePng 'view_empty') }
                $act = [ordered]@{ ActionID = (New-Uuid); LinkedTitle = $true; Name = 'View slot'; Plugin = $plugin; Resources = $null
                                   Settings = [ordered]@{ slot = [int]$k.slot; mode = 'auto' }; State = 0
                                   States = @((New-State (Put-Image $png) $true 'bottom' 11)); UUID = "$PluginId.view" }
            } elseif ($k.status) {
                $p0 = Get-TilePng 'status'; $p1 = Get-TilePng 'status_lit'; $faces[$pos] = $p1; $titles[$pos] = "COCKPIT`nA320"
                $act = [ordered]@{ ActionID = (New-Uuid); LinkedTitle = $true; Name = 'ChasePlane status'; Plugin = $plugin; Resources = $null
                                   Settings = [ordered]@{}; State = 0
                                   States = @((New-State (Put-Image $p0) $true 'bottom' 10), (New-State (Put-Image $p1) $true 'bottom' 10)); UUID = "$PluginId.status" }
            } else {
                $combo = Get-Combo $k.cmd
                $png = Get-KeyPng $k.icon $k.label $k.cat $false; $faces[$pos] = $png
                if ($IsBridge) {
                    # plugin profile: the plugin presses the key the user has bound to this command in ChasePlane (the speed keys go through the Bridge)
                    $cmdStates = @((New-State (Put-Image $png)))
                    if ($BridgeLit -contains $k.cmd) { $cmdStates += (New-State (Put-Image (Get-KeyPng $k.icon $k.label $k.cat $true))) }      # the plugin lights these (active speed, head tracking on)
                    $act = [ordered]@{ ActionID = (New-Uuid); LinkedTitle = $true; Name = 'ChasePlane command'; Plugin = $plugin; Resources = $null
                                       Settings = [ordered]@{ command = $k.cmd }; State = 0
                                       States = $cmdStates; UUID = "$PluginId.cmd" }
                } else {
                    $hk = @((New-Hotkey $combo), (New-EmptyHotkey), (New-EmptyHotkey), (New-EmptyHotkey))
                    $act = [ordered]@{ ActionID = (New-Uuid); LinkedTitle = $true; Name = 'Hotkey'
                                       Settings = [ordered]@{ Coalesce = $true; Hotkeys = $hk }
                                       State = 0; States = @((New-State (Put-Image $png))); UUID = 'com.elgato.streamdeck.system.hotkey' }
                    if ($v3) { $act['Plugin'] = $hkPlugin; $act['Resources'] = $null }
                }
                if (-not $seen.ContainsKey($k.cmd)) {
                    $seen[$k.cmd] = $true
                    if (-not ($IsBridge -and ($BridgeNative -contains $k.cmd))) {      # commands the Bridge does itself need no ChasePlane key
                        $used.Add([pscustomobject]@{ Command = $k.cmd; Keys = $combo; Page = $pi + 1; Button = ($k.label -replace "`n", ' ' -replace '- ', '') })
                    }
                }
            }
            $actions[$pos] = $act
        }
        $pageManifest = [ordered]@{ Controllers = (@([ordered]@{ Actions = $actions; Type = 'Keypad' }) + $extra); Icon = ''; Name = '' }
        Add-ZipBytes $zip "$dir/manifest.json" ($Utf8.GetBytes((To-Json $pageManifest)))
        if ($PreviewPrefix -and $Preview) {
            $script:PreviewData["$PreviewPrefix$($pi + 1)"] = @{ faces = $faces; titles = $titles; cols = $Dev.cols; rows = $Dev.rows; page = $page.name; dev = $Dev.key }
        }
    }
    $dd = if ($v3) { "$top/Profiles/$($defaultPage.ToUpper())" } else { "$top/Profiles/$(Encode-Id $defaultPage)" }
    Add-ZipDir $zip "$dd/"; Add-ZipDir $zip "$dd/Images/"
    $blank = @([ordered]@{ Actions = $null; Type = 'Keypad' }); foreach ($t in $Dev.extra) { $blank += [ordered]@{ Actions = $null; Type = $t } }
    Add-ZipBytes $zip "$dd/manifest.json" ($Utf8.GetBytes((To-Json ([ordered]@{ Controllers = $blank; Icon = ''; Name = '' }))))
    if ($v3) {
        $topManifest = [ordered]@{ Device = [ordered]@{ Model = $Dev.model; UUID = (New-Uuid) }; Name = $Name
                                   Pages = [ordered]@{ Current = '00000000-0000-0000-0000-000000000000'; Default = $defaultPage; Pages = @($pageIds) }; Version = '3.0' }
    } else {
        $topManifest = [ordered]@{ Device = [ordered]@{ Model = $Dev.model; UUID = '' }; Name = $Name
                                   Pages = [ordered]@{ Current = $pageIds[0]; Default = $defaultPage; Pages = @($pageIds) }; Version = '2.0' }
    }
    Add-ZipBytes $zip "$top/manifest.json" ($Utf8.GetBytes((To-Json $topManifest)))
    $zip.Dispose(); $fs.Dispose()
    , $used
}

# ---------------------------------------------------------------- items shared by all device layouts
# id -> hk = keyboard-command face (hotkeys-only profile) ; br = plugin action (plugin profile; falls back to hk when absent)
function HK($cmd, $label, $icon, $cat) { @{ cmd = $cmd; label = $label; icon = $icon; cat = $cat } }
$Items = @{
    cockpit     = @{ hk = (HK 'CAM_SET_ONBOARD' 'COCKPIT' 'cockpit' 'mode');           br = 'mode.cockpit' }
    external    = @{ hk = (HK 'CAM_SET_OUTSIDE' 'EXTERNAL' 'plane' 'mode');            br = 'mode.external' }
    world       = @{ hk = (HK 'CAM_SET_WORLD' 'WORLD' 'globe' 'world');                br = 'mode.world' }
    inout       = @{ hk = (HK 'CAM_TOGGLE_IN_OUT' 'IN / OUT' 'toggle' 'mode');         br = 'mode.toggle' }
    prevview    = @{ hk = (HK 'CAM_PREV_VIEW' "PREV`nVIEW" 'prev' 'nav') }
    nextview    = @{ hk = (HK 'CAM_NEXT_VIEW' "NEXT`nVIEW" 'next' 'nav') }
    reset       = @{ hk = (HK 'CAM_RESET' "RESET`nCAMERA" 'reset' 'reset') }
    cinematic   = @{ hk = (HK 'CAM_SET_CINEMATIC' 'CINEMATIC' 'clapper' 'smart');      br = 'cinematic.toggle' }
    nextcine    = @{ hk = (HK 'CAM_NEXT_CINEMATIC' "NEXT`nCINEMA" 'clappernext' 'smart'); br = 'cinematic.next' }
    flashlight  = @{ hk = (HK 'CAM_FLASHLIGHT_TOGGLE' "FLASH-`nLIGHT" 'flashlight' 'fx'); br = 'flashlight.toggle' }
    tower       = @{ hk = (HK 'CAM_NEAR_TOWER' 'TOWER' 'tower' 'world');               br = 'near.tower' }
    runway      = @{ hk = (HK 'CAM_NEAR_RUNWAY' 'RUNWAY' 'runway' 'world');            br = 'near.runway' }
    parking     = @{ hk = (HK 'CAM_NEAR_PARKING' 'PARKING' 'parking' 'world');         br = 'near.parking' }
    spotting    = @{ hk = (HK 'CAM_NEAR_SPOTTING' 'SPOTTING' 'camera' 'world');        br = 'near.spotting' }
    traffic     = @{ hk = (HK 'CAM_NEAR_TRAFFIC' 'TRAFFIC' 'traffic' 'world');         br = 'world.traffic' }
    drone       = @{ hk = (HK 'CAM_SET_DRONE' 'DRONE' 'drone' 'world');                br = 'world.drone' }
    flyby       = @{ hk = (HK 'CAM_SET_FLYBY' 'FLYBY' 'flyby' 'world');                br = 'world.flyby' }
    overview    = @{ hk = (HK 'CAM_SET_OVERVIEW' 'OVERVIEW' 'overview' 'world') }
    smart       = @{ hk = (HK 'CAM_SMART_VIEW' "SMART`nVIEW" 'star' 'smart') }
    smarthold   = @{ hk = (HK 'CAM_SMART_VIEW_HOLD' "SMART`nHOLD" 'starhold' 'smart') }
    prevgroup   = @{ hk = (HK 'CAM_PREV_GROUP' "PREV`nGROUP" 'prev2' 'nav') }
    nextgroup   = @{ hk = (HK 'CAM_NEXT_GROUP' "NEXT`nGROUP" 'next2' 'nav') }
    bino        = @{ hk = (HK 'CAM_BINOCULARS' "BINO-`nCULARS" 'binoculars' 'fx') }
    binohold    = @{ hk = (HK 'CAM_BINOCULARS_HOLD' "BINO`n(HOLD)" 'binoculars' 'fx') }
    peekL       = @{ hk = (HK 'CAM_QUICK_VIEW_LEFT' "PEEK`nLEFT" 'eyeL' 'peek') }
    peekR       = @{ hk = (HK 'CAM_QUICK_VIEW_RIGHT' "PEEK`nRIGHT" 'eyeR' 'peek') }
    peekU       = @{ hk = (HK 'CAM_QUICK_VIEW_UP' "PEEK`nUP" 'eyeU' 'peek') }
    peekD       = @{ hk = (HK 'CAM_QUICK_VIEW_DOWN' "PEEK`nDOWN" 'eyeD' 'peek') }
    peekB       = @{ hk = (HK 'CAM_QUICK_VIEW_BEHIND' "PEEK`nBACK" 'eyeB' 'peek') }
    zoomin      = @{ hk = (HK 'CAM_ZOOM_IN' "ZOOM`nIN" 'zoomin' 'fx') }
    zoomout     = @{ hk = (HK 'CAM_ZOOM_OUT' "ZOOM`nOUT" 'zoomout' 'fx') }
    zoomreset   = @{ hk = (HK 'CAM_RESET_ZOOM' "RESET`nZOOM" 'zoomreset' 'reset') }
    mvL         = @{ hk = (HK 'CAM_MOVE_L' 'LEFT' 'mvleft' 'move') }
    mvR         = @{ hk = (HK 'CAM_MOVE_R' 'RIGHT' 'mvright' 'move') }
    mvF         = @{ hk = (HK 'CAM_MOVE_F' 'FORWARD' 'mvup' 'move') }
    mvB         = @{ hk = (HK 'CAM_MOVE_B' 'BACK' 'mvdown' 'move') }
    mvU         = @{ hk = (HK 'CAM_MOVE_U' 'UP' 'mvlift' 'move') }
    mvD         = @{ hk = (HK 'CAM_MOVE_D' 'DOWN' 'mvlower' 'move') }
    rotL        = @{ hk = (HK 'CAM_ROT_L' "LOOK`nLEFT" 'eyeL' 'peek') }
    rotR        = @{ hk = (HK 'CAM_ROT_R' "LOOK`nRIGHT" 'eyeR' 'peek') }
    rotU        = @{ hk = (HK 'CAM_ROT_U' "LOOK`nUP" 'eyeU' 'peek') }
    rotD        = @{ hk = (HK 'CAM_ROT_D' "LOOK`nDOWN" 'eyeD' 'peek') }
    rollL       = @{ hk = (HK 'CAM_ROLL_L' "ROLL`nLEFT" 'rotccw' 'peek') }
    rollR       = @{ hk = (HK 'CAM_ROLL_R' "ROLL`nRIGHT" 'rotcw' 'peek') }
    resetorient = @{ hk = (HK 'CAM_RESET_ORIENT' "RESET`nHORIZON" 'horizon' 'reset') }
    boost       = @{ hk = (HK 'CAM_BOOST_SET' "BOOST`n(HOLD)" 'bolt' 'speed') }
    nvg         = @{ hk = (HK 'CAM_TOGGLE_NVG' "NIGHT`nVISION" 'moon' 'fx') }
    nvgless     = @{ hk = (HK 'CAM_NVG_INTENSITY_LESS' "NVG`nLESS" 'moonminus' 'fx') }
    nvgmore     = @{ hk = (HK 'CAM_NVG_INTENSITY_MORE' "NVG`nMORE" 'moonplus' 'fx') }
    dof         = @{ hk = (HK 'CAM_TOGGLE_DOF' "DEPTH OF`nFIELD" 'focus' 'fx') }
    autofocus   = @{ hk = (HK 'CAM_TOGGLE_DOF_AUTOFOCUS' "AUTO`nFOCUS" 'autofocus' 'fx') }
    expless     = @{ hk = (HK 'CAM_EXPOSURE_LESS' "EXPOSURE`nLESS" 'sunminus' 'fx') }
    expmore     = @{ hk = (HK 'CAM_EXPOSURE_MORE' "EXPOSURE`nMORE" 'sunplus' 'fx') }
    head        = @{ hk = (HK 'CAM_HEAD_TRACKING_TOGGLE' "HEAD`nTRACKING" 'head' 'fx') }
}
# keys that only exist with the plugin (view slots, status) are replaced by these hotkeys in the hotkeys-only profiles
$SlotSubs = @('smart', 'smarthold', 'prevgroup', 'nextgroup', 'bino', 'flashlight', 'overview', 'binohold')
# pages of the small decks: name -> face of the "go to this page" key
$PageMeta = @{
    views  = @{ name = 'VIEWS';   icon = 'eye';       cat = 'tab1' }
    cam    = @{ name = 'CAMERA';  icon = 'cockpit';   cat = 'tab1' }
    world  = @{ name = 'WORLD';   icon = 'globe';     cat = 'tab2' }
    move   = @{ name = 'FLY CAM'; icon = 'drone';     cat = 'tab3' }
    fly2   = @{ name = 'FLY 2';   icon = 'drone';     cat = 'tab3' }
    look   = @{ name = 'LOOK';    icon = 'eyeR';      cat = 'tabL' }
    rotate = @{ name = 'ROTATE';  icon = 'rotcw';     cat = 'tabL' }
    cinema = @{ name = 'CINEMA';  icon = 'clapper';   cat = 'tabC' }
    fx     = @{ name = 'FX';      icon = 'sun';       cat = 'tab4' }
    fx2    = @{ name = 'FX 2';    icon = 'sun';       cat = 'tab4' }
}
function Get-Cell([string]$id, [bool]$bridge, [int]$c, [int]$r) {
    if ($id -match '^slot(\d+)$') { return (V $c $r ([int]$Matches[1])) }
    if ($id -eq 'status') { return (S $c $r) }
    $it = $Items[$id]
    if ($null -eq $it) { throw "Unknown layout item '$id'" }
    if ($bridge -and $it.br) { return (B $c $r $it.br) }
    $h = $it.hk
    K $c $r $h.cmd $h.label $h.icon $h.cat
}

# Layout rows: one string per key row, one token per column. '-' = empty, '@page' = tab for that page,
# '>>' = "next page" key (small decks), 'slotN' / 'status' = plugin keys, anything else = an item id.
function New-GridPages($Dev, [bool]$bridge) {
    $names = @($Dev.pages | ForEach-Object { $_.p })
    $out = @()
    for ($pi = 0; $pi -lt $Dev.pages.Count; $pi++) {
        $pg = $Dev.pages[$pi]; $keys = @(); $present = @{}
        foreach ($row in $pg.rows) { foreach ($t in ($row -split '\s+')) { $present[$t] = $true } }
        $subs = New-Object System.Collections.Generic.Queue[string]
        foreach ($s in $SlotSubs) { if (-not $present.ContainsKey($s)) { $subs.Enqueue($s) } }
        if ($pg.rows.Count -ne $Dev.rows) { throw "Layout $($Dev.key)/$($pg.p) has $($pg.rows.Count) rows, expected $($Dev.rows)" }
        for ($r = 0; $r -lt $pg.rows.Count; $r++) {
            $tok = @($pg.rows[$r] -split '\s+')
            if ($tok.Count -ne $Dev.cols) { throw "Layout $($Dev.key)/$($pg.p) row $r has $($tok.Count) cells, expected $($Dev.cols)" }
            for ($c = 0; $c -lt $tok.Count; $c++) {
                $t = $tok[$c]
                if ($t -eq '-') { continue }
                if ($t.StartsWith('@') -or $t -eq '>>') {
                    $target = if ($t -eq '>>') { ($pi + 1) % $names.Count } else { [array]::IndexOf($names, $t.Substring(1)) }
                    if ($target -lt 0) { throw "Unknown page '$t' in layout of $($Dev.key)" }
                    $m = $PageMeta[$names[$target]]
                    $keys += @{ c = $c; r = $r; tab = $target + 1; label = $m.name; icon = $m.icon; cat = $m.cat }
                    continue
                }
                if (-not $bridge -and ($t -match '^slot\d+$' -or $t -eq 'status')) {
                    if ($t -eq 'status' -and -not $present.ContainsKey('reset')) { $t = 'reset'; $present['reset'] = $true }
                    elseif ($subs.Count -gt 0) { $t = $subs.Dequeue() }
                    else { continue }
                }
                $keys += (Get-Cell $t $bridge $c $r)
            }
        }
        $out += @{ name = $pg.p; keys = $keys }
    }
    , $out
}
# XL: the hand-placed layout above (tab bar + 4 global keys + page keys)
function Get-XlPages([bool]$bridge) {
    $src = if ($bridge) { $PagesBridge } else { $Pages }; $glob = if ($bridge) { $GlobalBridge } else { $Global }
    $out = @()
    foreach ($p in $src) {
        $keys = @(); foreach ($k in (@($TabBar) + @($glob) + @($p.keys))) { $keys += $k.Clone() }
        $out += @{ name = $p.name; keys = $keys }
    }
    , $out
}
# Plus XL (9x4): the XL layout plus one extra column with always-available camera modes
function Get-PlusXlPages([bool]$bridge) {
    $out = Get-XlPages $bridge
    foreach ($p in $out) {
        $p.keys += (Get-Cell 'cinematic' $bridge 8 0); $p.keys += (Get-Cell 'cockpit' $bridge 8 1)
        $p.keys += (Get-Cell 'external' $bridge 8 2);  $p.keys += (Get-Cell 'world' $bridge 8 3)
    }
    , $out
}
# Studio (16x2): the XL page content (3 rows of 8) flows into row 0 (right half) and row 1 (16 keys)
function Get-StudioPages([bool]$bridge) {
    $out = Get-XlPages $bridge
    foreach ($p in $out) {
        foreach ($k in $p.keys) {
            if ($k.r -ge 1) { $i = ($k.r - 1) * 8 + $k.c; if ($i -lt 8) { $k.c = 8 + $i; $k.r = 0 } else { $k.c = $i - 8; $k.r = 1 } }
        }
    }
    , $out
}
function Get-DevicePages($Dev, [bool]$bridge) {
    if ($Dev.kind -eq 'grid')   { return (New-GridPages $Dev $bridge) }
    if ($Dev.kind -eq 'xl')     { return (Get-XlPages $bridge) }
    if ($Dev.kind -eq 'plusxl') { return (Get-PlusXlPages $bridge) }
    if ($Dev.kind -eq 'studio') { return (Get-StudioPages $bridge) }
    throw "Unknown device kind $($Dev.kind)"
}

# ---------------------------------------------------------------- devices
# type = DeviceType of the plugin manifest; model = id of the Stream Deck app; extra = non-key controllers of the model
$TabRow5 = '@views @world @move @look @fx'
$Devices = @(
    @{ key = 'std'; file = 'Standard'; name = 'ChasePlane'; desc = 'Stream Deck / MK.2 / Scissor Keys (15 keys, 5x3)'; type = 0; model = '20GBA9901'; cols = 5; rows = 3; kind = 'grid'; extra = @(); hkFormat = 'v2'
       pages = @(
         @{ p = 'views'; rows = @($TabRow5, 'cockpit external world prevview nextview', 'slot1 slot2 slot3 slot4 status') }
         @{ p = 'world'; rows = @($TabRow5, 'tower runway parking spotting traffic', 'drone flyby cinematic nextcine flashlight') }
         @{ p = 'move';  rows = @($TabRow5, 'mvL mvF mvR mvU zoomin', 'mvD mvB boost reset zoomout') }
         @{ p = 'look';  rows = @($TabRow5, 'rotL rotU rotR rollL rollR', 'peekL rotD peekR peekB resetorient') }
         @{ p = 'fx';    rows = @($TabRow5, 'flashlight cinematic nextcine bino dof', 'nvg nvgless nvgmore expless expmore') }
       ) }
    @{ key = 'mini'; file = 'Mini'; name = 'ChasePlane Mini'; desc = 'Stream Deck Mini (6 keys, 3x2)'; type = 1; model = '20GAI9901'; cols = 3; rows = 2; kind = 'grid'; extra = @(); hkFormat = 'v2'
       pages = @(
         @{ p = 'cam';    rows = @('cockpit external world', 'prevview nextview >>') }
         @{ p = 'views';  rows = @('slot1 slot2 slot3', 'slot4 slot5 >>') }
         @{ p = 'world';  rows = @('tower runway parking', 'spotting traffic >>') }
         @{ p = 'look';   rows = @('peekL peekR zoomin', 'zoomout reset >>') }
         @{ p = 'cinema'; rows = @('cinematic nextcine drone', 'flyby flashlight >>') }
         @{ p = 'move';   rows = @('mvL mvF mvR', 'mvB boost >>') }
         @{ p = 'fly2';   rows = @('mvU mvD resetorient', 'rotL rotR >>') }
         @{ p = 'fx';     rows = @('nvg bino dof', 'expless expmore >>') }
       ) }
    @{ key = 'xl'; file = 'XL'; name = 'ChasePlane XL'; desc = 'Stream Deck XL (32 keys, 8x4)'; type = 2; model = '20GAT9901'; cols = 8; rows = 4; kind = 'xl'; extra = @(); hkFormat = 'v2' }
    @{ key = 'plus'; file = 'Plus'; name = 'ChasePlane Plus'; desc = 'Stream Deck + (8 keys, 4x2)'; type = 7; model = '20GBD9901'; cols = 4; rows = 2; kind = 'grid'; extra = @('Encoder'); hkFormat = 'v2'; pages = $null }
    @{ key = 'neo'; file = 'Neo'; name = 'ChasePlane Neo'; desc = 'Stream Deck Neo (8 keys, 4x2)'; type = 9; model = '20GBJ9901'; cols = 4; rows = 2; kind = 'grid'; extra = @('Neo'); hkFormat = 'v2'; pages = $null }
    @{ key = 'plusxl'; file = 'PlusXL'; name = 'ChasePlane Plus XL'; desc = 'Stream Deck + XL (36 keys, 9x4)'; type = 13; model = '20GBX9901'; cols = 9; rows = 4; kind = 'plusxl'; extra = @('Encoder'); hkFormat = 'v3' }
    @{ key = 'studio'; file = 'Studio'; name = 'ChasePlane Studio'; desc = 'Stream Deck Studio (32 keys, 16x2)'; type = 10; model = '20GBL9901'; cols = 16; rows = 2; kind = 'studio'; extra = @('Encoder'); hkFormat = 'v3' }
)
# Neo and Plus share the 4x2 layout
$Pages4x2 = @(
    @{ p = 'cam';    rows = @('cockpit external world inout', 'prevview nextview reset >>') }
    @{ p = 'views';  rows = @('slot1 slot2 slot3 slot4', 'slot5 slot6 slot7 >>') }
    @{ p = 'world';  rows = @('tower runway parking spotting', 'traffic drone flyby >>') }
    @{ p = 'look';   rows = @('peekL peekR peekU peekD', 'peekB zoomin zoomout >>') }
    @{ p = 'move';   rows = @('mvL mvF mvR mvU', 'mvB mvD boost >>') }
    @{ p = 'rotate'; rows = @('rotL rotU rotR rollL', 'rollR rotD resetorient >>') }
    @{ p = 'fx';     rows = @('flashlight cinematic nextcine bino', 'nvg nvgless nvgmore >>') }
    @{ p = 'fx2';    rows = @('dof autofocus expless expmore', 'head zoomreset - >>') }
)
foreach ($d in $Devices) { if ($d.key -eq 'plus' -or $d.key -eq 'neo') { $d.pages = $Pages4x2 } }

# ---------------------------------------------------------------- build all profiles
$script:PreviewData = @{}
$HkDir      = Join-Path $Root 'hotkeys-only'
$PluginDir  = Join-Path $Root 'plugin\com.chaseplanexl.deck.sdPlugin'
$PluginFile = Join-Path $Root 'ChasePlane XL.streamDeckPlugin'
$ProfilesDir = Join-Path $PluginDir 'Profiles'
New-Item -ItemType Directory -Force -Path $ProfilesDir | Out-Null
# remove outputs of earlier versions
foreach ($old in (Join-Path $Root 'ChasePlane XL.streamDeckProfile'), (Join-Path $Root 'ChasePlane XL (hotkeys only).streamDeckProfile')) { if (Test-Path $old) { Remove-Item $old -Force } }
if (Test-Path $HkDir) { Get-ChildItem $HkDir -Filter *.streamDeckProfile -File | Remove-Item -Force }
Get-ChildItem $ProfilesDir -Filter *.streamDeckProfile -File | Remove-Item -Force

$usedHotkeyXl = $null; $hybridCmds = @{}; $allUsed = @{}; $report = @()
foreach ($d in $Devices) {
    $hkPages = Get-DevicePages $d $false
    $brPages = Get-DevicePages $d $true
    $hkFile = Join-Path $HkDir "ChasePlane $($d.file) (hotkeys only).streamDeckProfile"
    $brFile = Join-Path $ProfilesDir "ChasePlane.$($d.file).streamDeckProfile"
    $usedHk = Build-Profile $hkPages $hkFile "$($d.name) (hotkeys)" "$($d.key)_hk_" $d $d.hkFormat $false
    $usedBr = Build-Profile $brPages $brFile $d.name "$($d.key)_br_" $d 'v3' $true
    if ($d.key -eq 'xl') { $usedHotkeyXl = $usedHk }
    foreach ($u in $usedHk) { $allUsed[$u.Command] = $true }
    foreach ($u in $usedBr) { $allUsed[$u.Command] = $true; if ($d.key -eq 'xl' -or -not $hybridCmds.ContainsKey($u.Command)) { $hybridCmds[$u.Command] = if ($d.key -eq 'xl') { $u.Page } else { '' } } }
    $report += ('{0,-7} {1,2} pages  plugin profile {2} KB  hotkeys-only {3} KB' -f $d.key, $brPages.Count, [math]::Round((Get-Item $brFile).Length / 1KB), [math]::Round((Get-Item $hkFile).Length / 1KB))
}
foreach ($cmd in $allUsed.Keys) { if (-not ($usedHotkeyXl | Where-Object { $_.Command -eq $cmd })) { throw "Command $cmd is used on a smaller deck but not on the XL layout; add it to the XL pages so the keymap csv lists it" } }

# keymap csv (rows = commands of the XL hotkeys-only profile; InHybrid = needed by any plugin profile)
$csv = New-Object System.Collections.Generic.List[string]
$csv.Add('Command,Keys,Status,Page,Button,InHybrid,HybridPage')
foreach ($u in $usedHotkeyXl) {
    $status = if ($Existing.ContainsKey($u.Command)) { 'existing' } else { 'new' }
    $inH = if ($hybridCmds.ContainsKey($u.Command)) { 'yes' } else { 'no' }
    $hp = if ($hybridCmds.ContainsKey($u.Command)) { $hybridCmds[$u.Command] } else { '' }
    $csv.Add("$($u.Command),$($u.Keys),$status,$($u.Page),""$($u.Button)"",$inH,$hp")
}
[System.IO.File]::WriteAllLines($CsvFile, $csv, (New-Object System.Text.UTF8Encoding $false))
$usedHybridCount = @($hybridCmds.Keys).Count

# the plugin manifest must list every bundled profile
$mf = Get-Content (Join-Path $PluginDir 'manifest.json') -Raw | ConvertFrom-Json
foreach ($d in $Devices) {
    $e = @($mf.Profiles | Where-Object { $_.Name -eq "Profiles/ChasePlane.$($d.file)" -and $_.DeviceType -eq $d.type })
    if ($e.Count -ne 1) { throw "manifest.json has no Profiles entry 'Profiles/ChasePlane.$($d.file)' with DeviceType $($d.type)" }
}
if (@($mf.Profiles).Count -ne $Devices.Count) { throw 'manifest.json lists profiles that are not built (or the other way round)' }

# ---------------------------------------------------------------- plugin assets (key faces) + package
$actDir = Join-Path $PluginDir 'imgs\actions'; $keyDir = Join-Path $PluginDir 'imgs\keys'; $plgDir = Join-Path $PluginDir 'imgs\plugin'
foreach ($d in $actDir, $keyDir, $plgDir) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
function Save-Face([string]$base, [byte[]]$png) {
    [System.IO.File]::WriteAllBytes("$base.png", (Resize-Png $png 72)); [System.IO.File]::WriteAllBytes("$base@2x.png", (Resize-Png $png 144))
}
foreach ($id in $BridgeActions.Keys) {
    $a = $BridgeActions[$id]
    Save-Face (Join-Path $actDir $id) (Get-KeyPng $a.icon $a.label $a.cat $false)
    Save-Face (Join-Path $actDir "${id}_lit") (Get-KeyPng $a.icon $a.label $a.cat $true)
}
Save-Face (Join-Path $actDir 'cmd') (Get-KeyPng 'bolt' '' 'speed' $false)
Save-Face (Join-Path $actDir 'cmd_lit') (Get-KeyPng 'bolt' '' 'speed' $true)
Save-Face (Join-Path $actDir 'view') (Get-TilePng 'view_m0')
Save-Face (Join-Path $actDir 'status') (Get-TilePng 'status'); Save-Face (Join-Path $actDir 'status_lit') (Get-TilePng 'status_lit')
foreach ($n in 'view_m0', 'view_m0_lit', 'view_m1', 'view_m1_lit', 'view_m2', 'view_m2_lit', 'view_empty', 'view_offline') { [System.IO.File]::WriteAllBytes((Join-Path $keyDir "$n.png"), (Get-TilePng $n)) }
$iconPng = Get-KeyPng 'overview' '' 'mode' $false 60 40
[System.IO.File]::WriteAllBytes((Join-Path $plgDir 'icon.png'), (Resize-Png $iconPng 256)); [System.IO.File]::WriteAllBytes((Join-Path $plgDir 'icon@2x.png'), (Resize-Png $iconPng 512))
[System.IO.File]::WriteAllBytes((Join-Path $plgDir 'category.png'), (Resize-Png $iconPng 28)); [System.IO.File]::WriteAllBytes((Join-Path $plgDir 'category@2x.png'), (Resize-Png $iconPng 56))

# keysend.exe: the helper that presses keys for the "command" keys (compiled with the csc.exe that ships with Windows)
$Csc = 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$KeySendExe = Join-Path $PluginDir 'bin\keysend.exe'
& $Csc /nologo /target:exe /optimize+ /platform:anycpu "/out:$KeySendExe" (Join-Path $Root 'plugin\keysend\KeySend.cs')
if ($LASTEXITCODE -ne 0) { throw "csc failed for keysend.exe ($LASTEXITCODE)" }

# .streamDeckPlugin = zip of the .sdPlugin folder (without logs)
if (Test-Path $PluginFile) { Remove-Item $PluginFile -Force }
$fs = [System.IO.File]::Open($PluginFile, [System.IO.FileMode]::CreateNew)
$zip = New-Object System.IO.Compression.ZipArchive($fs, [System.IO.Compression.ZipArchiveMode]::Create)
$base = Split-Path $PluginDir -Leaf; $n = 0
Get-ChildItem $PluginDir -Recurse -File | Where-Object { $_.FullName -notmatch '\\logs\\' } | ForEach-Object {
    $rel = $_.FullName.Substring($PluginDir.Length + 1).Replace('\', '/')
    Add-ZipBytes $zip "$base/$rel" ([System.IO.File]::ReadAllBytes($_.FullName)); $n++
}
$zip.Dispose(); $fs.Dispose()

Write-Host "Plugin  : $PluginFile ($([math]::Round((Get-Item $PluginFile).Length / 1KB)) KB, $n files)"
$report | ForEach-Object { Write-Host "  $_" }
Write-Host "Hotkeys : $HkDir"
Write-Host "Keymap  : $CsvFile ($($csv.Count - 1) commands, $usedHybridCount used by the plugin profiles)"

# ---------------------------------------------------------------- optional preview sheets: one image per model, all pages stacked
function Write-Montage([string]$prefix, [string]$outFile, [string]$title) {
    $keysOf = @($script:PreviewData.Keys | Where-Object { $_ -like "$prefix*" } | Sort-Object { [int]($_.Split('_')[-1]) })
    if ($keysOf.Count -eq 0) { return }
    $kw = 112; $gp = 6; $head = 34
    $cols = $script:PreviewData[$keysOf[0]].cols; $rows = $script:PreviewData[$keysOf[0]].rows
    $w = $cols * ($kw + $gp) + $gp; $ph = $head + $rows * ($kw + $gp) + $gp
    $sheet = New-Object System.Drawing.Bitmap $w, ($ph * $keysOf.Count)
    $g = [System.Drawing.Graphics]::FromImage($sheet); $g.Clear([System.Drawing.Color]::FromArgb(255, 5, 5, 6))
    $g.InterpolationMode = 'HighQualityBicubic'; $g.TextRenderingHint = 'AntiAliasGridFit'
    $hf = New-Object System.Drawing.Font('Segoe UI', 17, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
    $tf = New-Object System.Drawing.Font('Segoe UI', [single]($kw * 0.165), [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
    $sf = New-Object System.Drawing.StringFormat; $sf.Alignment = 'Center'; $sf.LineAlignment = 'Far'
    $dim = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 150, 156, 168))
    for ($i = 0; $i -lt $keysOf.Count; $i++) {
        $pd = $script:PreviewData[$keysOf[$i]]; $y0 = $i * $ph
        $cap = if ($w -ge 600) { "{0}  -  page {1}/{2}: {3}" -f $title, ($i + 1), $keysOf.Count, $pd.page.ToUpper() } else { "page {0}/{1}: {2}" -f ($i + 1), $keysOf.Count, $pd.page.ToUpper() }
        $g.DrawString($cap, $hf, $dim, 8, ($y0 + 7))
        foreach ($kv in $pd.faces.GetEnumerator()) {
            $cr = $kv.Key.Split(','); $x = $gp + [int]$cr[0] * ($kw + $gp); $y = $y0 + $head + $gp + [int]$cr[1] * ($kw + $gp)
            $img = [System.Drawing.Image]::FromStream((New-Object System.IO.MemoryStream (, [byte[]]$kv.Value)))
            $g.DrawImage($img, $x, $y, $kw, $kw); $img.Dispose()
            if ($pd.titles.ContainsKey($kv.Key)) {
                $rect = New-Object System.Drawing.RectangleF ($x + 3), ($y + 3), ($kw - 6), ($kw - 10)
                $g.DrawString($pd.titles[$kv.Key], $tf, [System.Drawing.Brushes]::White, $rect, $sf)
            }
        }
    }
    $g.Dispose(); $sheet.Save($outFile, [System.Drawing.Imaging.ImageFormat]::Png); $sheet.Dispose()
}
# optional: CP_PREVIEW_RAW = folder for one sharp sheet per page of every plugin profile (144 px keys, no gaps, example view names), used to draw promo images
if ($Preview -and $env:CP_PREVIEW_RAW) {
    New-Item -ItemType Directory -Force -Path $env:CP_PREVIEW_RAW | Out-Null
    foreach ($name in @($script:PreviewData.Keys | Where-Object { $_ -like '*_br_*' })) {
        $pd = $script:PreviewData[$name]; $kw = 144
        $sheet = New-Object System.Drawing.Bitmap ($pd.cols * $kw), ($pd.rows * $kw)
        $g = [System.Drawing.Graphics]::FromImage($sheet); $g.InterpolationMode = 'HighQualityBicubic'; $g.TextRenderingHint = 'AntiAliasGridFit'
        $tf = New-Object System.Drawing.Font('Segoe UI', [single]($kw * 0.165), [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
        $sf = New-Object System.Drawing.StringFormat; $sf.Alignment = 'Center'; $sf.LineAlignment = 'Far'
        foreach ($kv in $pd.faces.GetEnumerator()) {
            $cr = $kv.Key.Split(','); $x = [int]$cr[0] * $kw; $y = [int]$cr[1] * $kw
            $img = [System.Drawing.Image]::FromStream((New-Object System.IO.MemoryStream (, [byte[]]$kv.Value)))
            $g.DrawImage($img, $x, $y, $kw, $kw); $img.Dispose()
            if ($pd.titles.ContainsKey($kv.Key)) { $g.DrawString($pd.titles[$kv.Key], $tf, [System.Drawing.Brushes]::White, (New-Object System.Drawing.RectangleF ($x + 3), ($y + 3), ($kw - 6), ($kw - 10)), $sf) }
        }
        $g.Dispose(); $sheet.Save((Join-Path $env:CP_PREVIEW_RAW "$name.png"), [System.Drawing.Imaging.ImageFormat]::Png); $sheet.Dispose()
    }
    Write-Host "Raw sheets: $env:CP_PREVIEW_RAW"
}
if ($Preview) {
    New-Item -ItemType Directory -Force -Path $Preview | Out-Null
    Get-ChildItem $Preview -Filter *.png -File | Remove-Item -Force
    foreach ($d in $Devices) {
        Write-Montage "$($d.key)_br_" (Join-Path $Preview "$($d.key).png") "$($d.desc) - plugin profile"
        Write-Montage "$($d.key)_hk_" (Join-Path $Preview "$($d.key)_hotkeys.png") "$($d.desc) - hotkeys only"
    }
    Write-Host "Preview : $Preview"
}
