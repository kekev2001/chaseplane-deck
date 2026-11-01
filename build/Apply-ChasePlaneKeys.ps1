# Adds the keyboard assignments that the "ChasePlane XL" Stream Deck profile needs to ChasePlane's user_settings.json.
# - Only the rows marked "new" in chaseplane-keymap.csv are added; ChasePlane's existing bindings stay untouched.
# - A timestamped backup is written next to the settings file first.
# - Close MSFS and ChasePlane before running this (ChasePlane rewrites the file while it runs).
# Run:  powershell -ExecutionPolicy Bypass -File build\Apply-ChasePlaneKeys.ps1
# Optional: -SettingsPath "<path to user_settings.json>"   -DryRun
# Keep this file ASCII-only (Windows PowerShell 5.1 reads BOM-less UTF-8 as ANSI).
param(
    [string]$SettingsPath,
    [switch]$DryRun,
    [switch]$SkipProcessCheck,
    [switch]$HybridOnly      # only the keys that the plugin profile still needs (skips keys only the hotkeys-only profile uses)
)
$ErrorActionPreference = 'Stop'
$Csv = Join-Path (Split-Path $PSScriptRoot -Parent) 'chaseplane-keymap.csv'
if (-not (Test-Path $Csv)) { throw "Not found: $Csv (run Build-ChasePlaneXL.ps1 first)" }

if (-not $SettingsPath) {
    $candidates = @(
        "$env:APPDATA\Microsoft Flight Simulator 2024\WASM\MSFS2024\p42-util-chaseplane\work\user_settings.json",
        "$env:LOCALAPPDATA\Packages\Microsoft.Limitless_8wekyb3d8bbwe\LocalState\WASM\MSFS2024\p42-util-chaseplane\work\user_settings.json",
        "$env:APPDATA\Microsoft Flight Simulator\Packages\p42-util-chaseplane\work\user_settings.json",
        "$env:LOCALAPPDATA\Packages\Microsoft.FlightSimulator_8wekyb3d8bbwe\LocalState\packages\p42-util-chaseplane\work\user_settings.json"
    )
    $found = @($candidates | Where-Object { Test-Path $_ })
    if ($found.Count -eq 0) { throw 'ChasePlane user_settings.json not found. Pass -SettingsPath.' }
    if ($found.Count -gt 1) { Write-Host 'More than one ChasePlane settings file found:'; $found | ForEach-Object { Write-Host "  $_" }; throw 'Pass the one you want with -SettingsPath.' }
    $SettingsPath = $found[0]
}
if (-not (Test-Path $SettingsPath)) { throw "Not found: $SettingsPath" }

if (-not $DryRun -and -not $SkipProcessCheck) {
    $running = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match 'FlightSimulator|ChasePlane' })
    if ($running.Count -gt 0) { throw ('Close these first: ' + (($running | Select-Object -ExpandProperty ProcessName -Unique) -join ', ')) }
}

function Get-Vk([string]$key) {
    if ($key -match '^[A-Z0-9]$') { return [int][char]$key }
    if ($key -match '^F(\d+)$') { return 111 + [int]$Matches[1] }
    switch ($key) { 'Shift' { 160 } 'Ctrl' { 162 } 'Alt' { 164 } default { throw "Unknown key $key" } }
}
function Get-Entry([string]$combo) {
    # modifiers first (Shift, Ctrl, Alt order as ChasePlane stores them), then the key
    $parts = $combo.Split('+'); $out = ''
    foreach ($m in 'Shift', 'Ctrl', 'Alt') { if ($parts -contains $m) { $out += "1|Keyboard|$(Get-Vk $m)|2|0;" } }
    $out + "1|Keyboard|$(Get-Vk $parts[$parts.Length - 1])|2|0;"
}

$bytes = [System.IO.File]::ReadAllBytes($SettingsPath)
$hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
$text = [System.Text.Encoding]::UTF8.GetString($bytes); if ($hasBom) { $text = $text.Substring(1) }

$rx = [regex]'("control_mappings"\s*:\s*")((?:[^"\\]|\\.)*)(")'
$m = $rx.Match($text)
if (-not $m.Success) { throw 'control_mappings not found in the settings file.' }
$body = $m.Groups[2].Value

# keep the escape style of the file itself ("\u0026" in ChasePlane's own JSON)
$sep = if ($body.Contains('\u0026') -or $body.Length -eq 0) { '\u0026' } else { '&' }
$added = @(); $skipped = @()
foreach ($row in (Import-Csv $Csv | Where-Object { $_.Status -eq 'new' -and (-not $HybridOnly -or $_.InHybrid -eq 'yes') })) {
    $line = $row.Command + $sep + (Get-Entry $row.Keys)
    if ($body.Contains($line)) { $skipped += $row.Command; continue }
    $body += $line + '\n'
    $added += "{0,-30} {1}" -f $row.Command, $row.Keys
}
$added | ForEach-Object { Write-Host "  + $_" }
Write-Host ("Added {0}, already present {1}." -f $added.Count, $skipped.Count)
if ($DryRun) { Write-Host 'Dry run: nothing written.'; return }
if ($added.Count -eq 0) { return }

$newText = $text.Substring(0, $m.Groups[2].Index) + $body + $text.Substring($m.Groups[2].Index + $m.Groups[2].Length)
$null = $newText | ConvertFrom-Json          # must still be valid JSON
$backup = "$SettingsPath.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
Copy-Item $SettingsPath $backup
$enc = New-Object System.Text.UTF8Encoding $hasBom
[System.IO.File]::WriteAllText($SettingsPath, $newText, $enc)
Write-Host "Written : $SettingsPath"
Write-Host "Backup  : $backup  (copy it back over the original to undo)"
