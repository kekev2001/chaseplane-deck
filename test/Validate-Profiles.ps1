# Structural check of every generated profile (plugin-bundled V3 profiles and hotkeys-only profiles).
# Run:  powershell -ExecutionPolicy Bypass -File test\Validate-Profiles.ps1
# Checks: zip layout (V2 / V3), manifest JSON, page count, keys inside the model's grid, no duplicate keys,
# every image reference exists, tab / next-page targets exist, plugin action ids exist in the plugin manifest,
# plugin manifest lists exactly the bundled profiles with the right DeviceType.
# Keep this file ASCII-only (Windows PowerShell 5.1 reads BOM-less UTF-8 as ANSI).
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$Root = Split-Path $PSScriptRoot -Parent
$PluginDir = Join-Path $Root 'plugin\com.chaseplanexl.deck.sdPlugin'
$Grid = @{ '20GBA9901' = @(5, 3); '20GAI9901' = @(3, 2); '20GAT9901' = @(8, 4); '20GBD9901' = @(4, 2); '20GBJ9901' = @(4, 2); '20GBX9901' = @(9, 4); '20GBL9901' = @(16, 2) }
$DeviceTypes = @{ '20GBA9901' = 0; '20GAI9901' = 1; '20GAT9901' = 2; '20GBD9901' = 7; '20GBJ9901' = 9; '20GBX9901' = 13; '20GBL9901' = 10 }
$GotoBase = 1
$fail = 0; $checks = 0
function Check([bool]$ok, [string]$msg) { $script:checks++; if (-not $ok) { $script:fail++; Write-Host "FAIL: $msg" -ForegroundColor Red } }
function Read-Entry($zip, [string]$name) {
    $e = $zip.GetEntry($name); if (-not $e) { return $null }
    $sr = New-Object System.IO.StreamReader($e.Open()); $t = $sr.ReadToEnd(); $sr.Close(); $t
}

$mf = Get-Content (Join-Path $PluginDir 'manifest.json') -Raw | ConvertFrom-Json
$pluginActions = @($mf.Actions | ForEach-Object { $_.UUID })
$pluginId = 'com.chaseplanexl.deck'

$files = @()
$files += Get-ChildItem (Join-Path $PluginDir 'Profiles') -Filter *.streamDeckProfile -File | ForEach-Object { @{ path = $_.FullName; bridge = $true; v3 = $true } }
$hkDir = Join-Path $Root 'hotkeys-only'
if (Test-Path $hkDir) { $files += Get-ChildItem $hkDir -Filter *.streamDeckProfile -File | ForEach-Object { @{ path = $_.FullName; bridge = $false; v3 = $null } } }
Check ($files.Count -ge 14) "expected 14 profiles (7 models x 2), found $($files.Count)"

foreach ($f in $files) {
    $label = (Split-Path $f.path -Leaf)
    $zip = [System.IO.Compression.ZipFile]::OpenRead($f.path)
    try {
        $names = @($zip.Entries | ForEach-Object { $_.FullName })
        Check (-not ($names | Where-Object { $_ -match '\\' })) "${label}: backslash in zip entry names"
        $isV3 = $names -contains 'package.json'
        if ($f.v3 -ne $null) { Check ($isV3 -eq $f.v3) "${label}: expected V3=$($f.v3)" }
        $prefix = ''
        if ($isV3) { $pkg = (Read-Entry $zip 'package.json') | ConvertFrom-Json; $model = $pkg.DeviceModel; $prefix = 'Profiles/' }
        $topDirs = @($names | Where-Object { $_ -match "^$prefix[^/]+\.sdProfile/$" })
        Check ($topDirs.Count -eq 1) "${label}: expected exactly one .sdProfile folder, found $($topDirs.Count)"
        $top = $topDirs[0].TrimEnd('/')
        $m = (Read-Entry $zip "$top/manifest.json") | ConvertFrom-Json
        if (-not $isV3) { $model = $m.Device.Model }
        Check ($m.Device.Model -eq $model) "${label}: model differs between package.json and manifest"
        Check ($Grid.ContainsKey($model)) "${label}: unknown model $model"
        Check ($m.Version -eq $(if ($isV3) { '3.0' } else { '2.0' })) "${label}: manifest Version is $($m.Version)"
        $cols = $Grid[$model][0]; $rows = $Grid[$model][1]
        $pageIds = @($m.Pages.Pages)
        Check ($pageIds.Count -ge 4) "${label}: only $($pageIds.Count) pages"
        Check ((@($pageIds | Select-Object -Unique)).Count -eq $pageIds.Count) "${label}: duplicate page ids"
        $pageDirs = @($names | Where-Object { $_ -match "^$([regex]::Escape($top))/Profiles/[^/]+/$" })
        Check ($pageDirs.Count -eq $pageIds.Count + 1) "${label}: $($pageDirs.Count) page folders for $($pageIds.Count) pages (+1 default expected)"
        if ($isV3) {
            foreach ($id in $pageIds) { Check ($names -contains "$top/Profiles/$($id.ToUpper())/manifest.json") "${label}: page folder for $id missing" }
        }
        $order = 0
        foreach ($pd in $pageDirs) {
            $pm = Read-Entry $zip ($pd + 'manifest.json'); if (-not $pm) { Check $false "${label}: $pd has no manifest.json"; continue }
            $j = $pm | ConvertFrom-Json
            $kp = @($j.Controllers | Where-Object { $_.Type -eq 'Keypad' })
            Check ($kp.Count -eq 1) "${label}: $pd has $($kp.Count) Keypad controllers"
            if ($kp.Count -ne 1 -or $null -eq $kp[0].Actions) { continue }
            $slots = @{}
            foreach ($p in $kp[0].Actions.PSObject.Properties) {
                $xy = $p.Name.Split(','); $c = [int]$xy[0]; $r = [int]$xy[1]
                Check ($c -lt $cols -and $r -lt $rows) "${label}: key $($p.Name) outside the $cols x $rows grid"
                $a = $p.Value
                foreach ($st in $a.States) {
                    if ($st.Image) { Check ($names -contains ($pd + $st.Image)) "${label}: image $($st.Image) missing for key $($p.Name)" }
                }
                if ($a.UUID -eq 'com.elgato.streamdeck.page.goto') {
                    $idx = [int]$a.Settings.PageIndex
                    Check ($idx -ge $GotoBase -and $idx -le ($pageIds.Count - 1 + $GotoBase)) "${label}: goto page index $idx out of range"
                } elseif ($a.UUID -like "$pluginId.*") {
                    Check ($pluginActions -contains $a.UUID) "${label}: action $($a.UUID) is not in the plugin manifest"
                    Check ($f.bridge) "${label}: plugin action in a hotkeys-only profile"
                    if ($a.UUID -eq "$pluginId.view") { $s = [int]$a.Settings.slot; Check (-not $slots.ContainsKey($s)) "${label}: view slot $s twice on one page"; $slots[$s] = $true }
                } elseif ($a.UUID -eq 'com.elgato.streamdeck.system.hotkey') {
                    Check (@($a.Settings.Hotkeys).Count -eq 4) "${label}: hotkey with $(@($a.Settings.Hotkeys).Count) entries"
                    Check ($a.Settings.Hotkeys[0].VKeyCode -gt 0) "${label}: empty first hotkey at $($p.Name)"
                } else { Check $false "${label}: unexpected action $($a.UUID)" }
            }
            Check ($f.bridge -or $slots.Count -eq 0) "${label}: view slots in a hotkeys-only profile"
            if ($kp[0].Actions.PSObject.Properties.Name.Count -gt 0) { $order++ }
        }
        Check ($order -eq $pageIds.Count) "${label}: $order pages with keys for $($pageIds.Count) pages"
        if ($f.bridge) {
            $stem = $label -replace '\.streamDeckProfile$', ''
            $ent = @($mf.Profiles | Where-Object { $_.Name -eq "Profiles/$stem" })
            Check ($ent.Count -eq 1) "${label}: not listed in the plugin manifest"
            if ($ent.Count -eq 1) { Check ($ent[0].DeviceType -eq $DeviceTypes[$model]) "${label}: manifest DeviceType $($ent[0].DeviceType), model $model needs $($DeviceTypes[$model])" }
        }
        Write-Host ("ok  {0,-48} {1}  {2,2} pages  {3}x{4}  {5}" -f $label, $(if ($isV3) { 'V3' } else { 'V2' }), $pageIds.Count, $cols, $rows, $model)
    } finally { $zip.Dispose() }
}
Check (@($mf.Profiles).Count -eq @($files | Where-Object { $_.bridge }).Count) 'plugin manifest lists a different number of profiles than are bundled'
Write-Host ("{0} checks, {1} failed" -f $checks, $fail)
if ($fail -gt 0) { exit 1 }
