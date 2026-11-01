# Tests of release\ChasePlane-Deck-Setup.exe through its command line. Works only on scratch copies: a synthetic user_settings.json,
# a scratch plugin folder (CPDECK_PLUGINS_DIR) and a local test server for the update check. It never touches ChasePlane's real settings,
# the real Stream Deck plugin folder or the Stream Deck app.
# Run:  powershell -ExecutionPolicy Bypass -File test\Test-Installer.ps1
# Keep this file ASCII-only (Windows PowerShell 5.1 reads BOM-less UTF-8 as ANSI).
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$Root = Split-Path $PSScriptRoot -Parent
$Exe = Join-Path $Root 'release\ChasePlane-Deck-Setup.exe'
$Work = Join-Path ([System.IO.Path]::GetTempPath()) ('cpdeck-test-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $Work | Out-Null
$Plugins = Join-Path $Work 'plugins'; New-Item -ItemType Directory -Force -Path $Plugins | Out-Null
$env:CPDECK_PLUGINS_DIR = $Plugins
$env:CPDECK_UPDATE_URL = ''
$pass = 0; $fail = 0
function Check([bool]$ok, [string]$msg) { if ($ok) { $script:pass++ } else { $script:fail++; Write-Host "FAIL: $msg" -ForegroundColor Red } }
function Run([string]$exeArgs) {
    $log = Join-Path $Work 'run.log'; if (Test-Path $log) { Remove-Item $log -Force }
    $p = Start-Process -FilePath $Exe -ArgumentList "$exeArgs /log:`"$log`"" -Wait -PassThru
    $text = if (Test-Path $log) { (Get-Content $log -Raw) } else { '' }
    [pscustomobject]@{ Code = $p.ExitCode; Log = $text }
}

# ---- synthetic ChasePlane settings: the default keyboard bindings the deck relies on + a mouse binding
function Vk([string]$k) { if ($k -match '^[A-Z0-9]$') { return [int][char]$k }; if ($k -match '^F(\d+)$') { return 111 + [int]$Matches[1] }; switch ($k) { 'Shift' { 160 } 'Ctrl' { 162 } 'Alt' { 164 } 'End' { 35 } 'PageUp' { 33 } 'Space' { 32 } } }
function Entry([string]$combo) { $parts = $combo.Split('+'); $o = ''; foreach ($m in 'Shift', 'Ctrl', 'Alt') { if ($parts -contains $m) { $o += "1|Keyboard|$(Vk $m)|2|0;" } }; $o + "1|Keyboard|$(Vk $parts[-1])|2|0;" }
$csv = Import-Csv (Join-Path $Root 'chaseplane-keymap.csv')
$lines = @(); foreach ($r in ($csv | Where-Object { $_.Status -eq 'existing' })) { $lines += ($r.Command + '&' + (Entry $r.Keys) + '\n') }
$lines += 'CAM_SMART_VIEW&0|Mouse|0|2|0;\n'
$Base = '{"version":3,"ui_compact":false,"control_mappings":"' + ($lines -join '') + '","named_assignments":[]}'
function NewSettings([string]$name, [string]$text = $Base) { $d = Join-Path $Work $name; New-Item -ItemType Directory -Force -Path $d | Out-Null; $f = Join-Path $d 'user_settings.json'; [System.IO.File]::WriteAllText($f, $text, (New-Object System.Text.UTF8Encoding $false)); $f }
function Lines([string]$f) { $j = Get-Content $f -Raw | ConvertFrom-Json; @($j.control_mappings -split "`n" | Where-Object { $_ }) }

# ---- 1. adding keys
$s1 = NewSettings 's1'
$r = Run "/silent /noplugin /dryrun /settings:`"$s1`""
Check ($r.Code -eq 0 -and $r.Log -match '21 to add') "dry run should report 21 keys: $($r.Log)"
Check ((Get-Content $s1 -Raw) -ceq $Base) 'dry run changed the file'
$r = Run "/silent /noplugin /settings:`"$s1`""
Check ($r.Code -eq 0 -and $r.Log -match '21 to add' -and $r.Log -match 'Backup:') "apply: $($r.Log)"
$n1 = (Lines $s1).Count
$r = Run "/silent /noplugin /settings:`"$s1`""
Check ($r.Log -match '0 to add, 21 already there') "second apply should add nothing: $($r.Log)"
Check ((Lines $s1).Count -eq $n1) 'second apply changed the number of lines'
$null = (Get-Content $s1 -Raw | ConvertFrom-Json)
$r = Run "/silent /noplugin /allkeys /settings:`"$s1`""
Check ($r.Log -match '18 to add' -and $r.Log -match 'skipped CAM_SMART_VIEW') "allkeys: $($r.Log)"

# ---- 2. removing exactly what was added gives the original back
$s2 = NewSettings 's2'
$null = Run "/silent /noplugin /allkeys /settings:`"$s2`""
Check ((Get-Content $s2 -Raw) -cne $Base) 'allkeys apply did not change the file'
$r = Run "/silent /remove /yes /noplugin /nostreamdeck /settings:`"$s2`""
Check ($r.Code -eq 0 -and $r.Log -match '39 keys to remove') "remove keys: $($r.Log)"
Check ((Get-Content $s2 -Raw) -ceq $Base) 'after removing the keys the file differs from the original'
$r = Run "/silent /remove /yes /noplugin /nostreamdeck /settings:`"$s2`""
Check ($r.Log -match '0 keys to remove') "removing twice: $($r.Log)"

# ---- 3. a user's own binding on the same keys, and a changed default, and the mouse binding
$own = $Base.Replace('"control_mappings":"', '"control_mappings":"CAM_OTHER_THING&1|Keyboard|164|2|0;1|Keyboard|162|2|0;1|Keyboard|127|2|0;\n')
$own = $own.Replace('CAM_QUICK_VIEW_LEFT&1|Keyboard|160|2|0;1|Keyboard|72|2|0;', 'CAM_QUICK_VIEW_LEFT&1|Keyboard|160|2|0;1|Keyboard|74|2|0;')
$s3 = NewSettings 's3' $own
$r = Run "/silent /noplugin /settings:`"$s3`""
Check ($r.Log -match 'CAM_QUICK_VIEW_BEHIND: Ctrl\+Alt\+F16 is already used by CAM_OTHER_THING' -and $r.Log -match '20 to add') "conflict: $($r.Log)"
Check ($r.Log -match 'CAM_QUICK_VIEW_LEFT uses a different key') "changed default not reported: $($r.Log)"
$r = Run "/silent /undo /settings:`"$s3`""
Check ((Get-Content $s3 -Raw) -ceq $own) 'undo did not restore the original'

# ---- 4. check & fix against a scratch plugin folder
$s4 = NewSettings 's4'
$r = Run "/silent /repair /dryrun /settings:`"$s4`""
Check ($r.Code -eq 1 -and $r.Log -match 'The plugin is not installed' -and $r.Log -match '21 keys are missing') "repair, nothing installed: $($r.Log)"
Check ($r.Log -match 'Bridge') 'bridge line missing'
[System.IO.Compression.ZipFile]::ExtractToDirectory((Join-Path $Root 'ChasePlane XL.streamDeckPlugin'), $Plugins)
$null = Run "/silent /noplugin /settings:`"$s4`""
$r = Run "/silent /repair /dryrun /settings:`"$s4`""
Check ($r.Code -eq 0 -and $r.Log -match 'installed \(1\.0\.0\.0\) and its files are intact' -and $r.Log -match 'All deck keys are set') "repair, healthy: $($r.Log)"
$pj = Join-Path $Plugins 'com.chaseplanexl.deck.sdPlugin\bin\plugin.js'
Add-Content $pj '// tampered'
$r = Run "/silent /repair /dryrun /settings:`"$s4`""
Check ($r.Code -eq 1 -and $r.Log -match 'damaged' -and $r.Log -match 'plugin\.js') "repair, damaged: $($r.Log)"
$mf = Join-Path $Plugins 'com.chaseplanexl.deck.sdPlugin\manifest.json'
$orig = [System.IO.File]::ReadAllText($mf)
[System.IO.File]::WriteAllText($mf, ($orig -replace '"Version": "1\.0\.0\.0"', '"Version": "0.9.0.0"'), (New-Object System.Text.UTF8Encoding $false))
$r = Run "/silent /repair /dryrun /settings:`"$s4`""
Check ($r.Code -eq 1 -and $r.Log -match 'out of date: installed 0\.9\.0\.0, this Setup has 1\.0\.0\.0') "repair, outdated: $($r.Log)"
[System.IO.File]::WriteAllText($mf, ($orig -replace '"Version": "1\.0\.0\.0"', '"Version": "2.0.0.0"'), (New-Object System.Text.UTF8Encoding $false))
$r = Run "/silent /repair /dryrun /settings:`"$s4`""
Check ($r.Log -match 'newer plugin \(2\.0\.0\.0\)') "repair, newer plugin: $($r.Log)"

# ---- 5. fixing missing keys through /repair (plugin step skipped)
$s5 = NewSettings 's5'
$r = Run "/silent /repair /noplugin /settings:`"$s5`""
Check ($r.Code -eq 0 -and (Lines $s5).Count -eq ((Lines (NewSettings 's5b')).Count + 21)) "repair should add 21 keys: $($r.Log)"

# ---- 6. removing the plugin and the ChasePlane profiles (profiles are folders in a scratch ProfilesV3 next to the scratch plugins folder)
$Prof = Join-Path $Work 'ProfilesV3'
function FakeProfile([string]$name, [string]$model = '20GAT9901') {
    $d = Join-Path $Prof ([guid]::NewGuid().ToString().ToUpper() + '.sdProfile'); New-Item -ItemType Directory -Force -Path $d | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $d 'manifest.json'), ('{"Device":{"Model":"' + $model + '","UUID":""},"Name":"' + $name + '","Pages":{"Current":"","Default":"","Pages":[]},"Version":"3.0"}'))
    $d
}
$pXL = FakeProfile 'ChasePlane XL'; $pHk = FakeProfile 'ChasePlane XL (hotkeys)'; $pMini = FakeProfile 'ChasePlane Mini' '20GAI9901'
$pOther = @((FakeProfile 'GSX'), (FakeProfile 'ChasePlane Deck'), (FakeProfile 'Default profile'))
$r = Run "/silent /remove /yes /nokeys /nostreamdeck /dryrun"
Check ($r.Log -match 'profile: ChasePlane XL' -and $r.Log -match 'profile: ChasePlane Mini' -and $r.Log -notmatch 'profile: GSX' -and (Test-Path $pXL) -and (Test-Path (Join-Path $Plugins 'com.chaseplanexl.deck.sdPlugin'))) "dry run must list the profiles but touch nothing: $($r.Log)"
$r = Run "/silent /remove /yes /nokeys /nostreamdeck /noprofiles"
Check ($r.Code -eq 0 -and $r.Log -match 'Plugin removed' -and -not (Test-Path (Join-Path $Plugins 'com.chaseplanexl.deck.sdPlugin')) -and (Test-Path $pXL)) "remove plugin only: $($r.Log)"
$r = Run "/silent /remove /yes /nokeys /nostreamdeck"
Check ($r.Code -eq 0 -and $r.Log -match 'not installed' -and $r.Log -match '3 profile\(s\) moved') "remove profiles: $($r.Log)"
Check (-not (Test-Path $pXL) -and -not (Test-Path $pHk) -and -not (Test-Path $pMini)) 'the ChasePlane profiles should be gone from ProfilesV3'
Check ((@($pOther | Where-Object { Test-Path $_ })).Count -eq 3) 'profiles that are not ours (GSX, a custom "ChasePlane Deck", Default) must stay'
$bk = @(Get-ChildItem $Work -Directory -Filter 'ChasePlaneDeck-removed-profiles-*')
Check ($bk.Count -eq 1 -and (@(Get-ChildItem $bk[0].FullName -Directory)).Count -eq 3) 'the moved profiles should be in one backup folder'
$r = Run "/silent /remove /yes /nokeys /nostreamdeck"
Check ($r.Log -match 'not installed' -and $r.Log -notmatch 'moved') "remove twice: $($r.Log)"
$r = Run "/silent /remove /nokeys /nostreamdeck"
Check ($r.Code -eq 1 -and $r.Log -match 'needs /yes') 'remove without /yes must refuse'

# ---- 7. running simulator: refuse to touch the settings
Copy-Item "$env:WINDIR\System32\timeout.exe" (Join-Path $Work 'FlightSimulator2024.exe') -Force
$dummy = Start-Process -FilePath (Join-Path $Work 'FlightSimulator2024.exe') -ArgumentList '/t 60 /nobreak' -PassThru -WindowStyle Hidden
Start-Sleep -Milliseconds 700
$s7 = NewSettings 's7'
$r = Run "/silent /noplugin /settings:`"$s7`""
Check ($r.Code -eq 1 -and $r.Log -match 'Close first: FlightSimulator2024') "running sim: $($r.Log)"
$r = Run "/silent /remove /yes /noplugin /settings:`"$s7`""
Check ($r.Code -eq 1 -and $r.Log -match 'Close MSFS') "remove while sim runs: $($r.Log)"
Check ((Get-Content $s7 -Raw) -ceq $Base) 'settings changed while the simulator ran'
Stop-Process -Id $dummy.Id -Force -ErrorAction SilentlyContinue

# ---- 8. Dutch
$s8 = NewSettings 's8'
$r = Run "/silent /noplugin /dryrun /lang:nl /settings:`"$s8`""
Check ($r.Log -match '21 toe te voegen' -and $r.Log -match 'proefrun') "dutch log: $($r.Log)"
$r = Run "/silent /repair /dryrun /lang:nl /settings:`"$s8`""
Check ($r.Log -match 'De plugin is niet' -and $r.Log -match 'toetsen ontbreken') "dutch repair: $($r.Log)"

# ---- 9. update check against a local server
$port = 18000 + (Get-Random -Maximum 1000)
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://127.0.0.1:$port/")
$listener.Start()
function Serve([string]$json) {
    $async = $listener.BeginGetContext($null, $null)
    $env:CPDECK_UPDATE_URL = "http://127.0.0.1:$port/latest.json"
    $ps = [powershell]::Create(); $null = $ps.AddScript({ param($u) $c = Start-Process -FilePath $u.exe -ArgumentList "/silent /checkupdate /log:`"$($u.log)`"" -Wait -PassThru; $c.ExitCode }).AddArgument(@{ exe = $Exe; log = (Join-Path $Work 'upd.log') })
    if (Test-Path (Join-Path $Work 'upd.log')) { Remove-Item (Join-Path $Work 'upd.log') -Force }
    $h = $ps.BeginInvoke()
    $ctx = $async.AsyncWaitHandle.WaitOne(8000)
    if ($ctx) { $c = $listener.EndGetContext($async); $bytes = [System.Text.Encoding]::UTF8.GetBytes($json); $c.Response.ContentType = 'application/json'; $c.Response.OutputStream.Write($bytes, 0, $bytes.Length); $c.Response.Close() }
    $null = $ps.EndInvoke($h); $ps.Dispose()
    if (Test-Path (Join-Path $Work 'upd.log')) { Get-Content (Join-Path $Work 'upd.log') -Raw } else { '(no log)' }
}
$u = Serve '{"version":"1.1.0.0","url":"https://example.com/ChasePlane-Deck-1.1.0.zip","notes":"Fixes peek keys"}'
Check ($u -match 'update 1\.1\.0\.0 https://example\.com/ChasePlane-Deck-1\.1\.0\.zip \| Fixes peek keys') "newer version: $u"
$u = Serve '{"version":"1.0.0.0","url":"https://example.com/x.zip"}'
Check ($u -match 'no update') "same version: $u"
$u = Serve '{"version":"9.0.0.0","url":"http://example.com/x.zip"}'
Check ($u -match 'no update') "non-https download link must be refused: $u"
$u = Serve '{"version":"9.0.0.0","url":"javascript:alert(1)"}'
Check ($u -match 'no update') "javascript link must be refused: $u"
$u = Serve 'this is not json'
Check ($u -match 'no update') "garbage: $u"
$listener.Stop()
$env:CPDECK_UPDATE_URL = 'http://example.com/latest.json'      # remote plain http must never be requested
$r = Run '/silent /checkupdate'
Check ($r.Log -match 'no update') "remote http source: $($r.Log)"
$env:CPDECK_UPDATE_URL = ''
$r = Run '/silent /checkupdate'
Check ($r.Log -match 'no update') "no address configured: $($r.Log)"

# ---- 10b. the hotkeys-only profiles travel inside the exe
$exp = Join-Path $Work 'hk'
$null = Run "/silent /exporthk:`"$exp`""
$same = $true; $count = 0
foreach ($f in (Get-ChildItem (Join-Path $Root 'hotkeys-only') -Filter *.streamDeckProfile)) { $count++; $t = Join-Path $exp $f.Name; if (-not (Test-Path $t) -or (Get-FileHash $t).Hash -ne (Get-FileHash $f.FullName).Hash) { $same = $false } }
Check ($same -and $count -eq 7 -and (@(Get-ChildItem $exp)).Count -eq 7) 'the 7 embedded hotkeys-only profiles must equal the files in hotkeys-only\'

# ---- 10c. the dialogs render in both languages
foreach ($dlg in 'help', 'remove', 'hk') {
    foreach ($lang in 'en', 'nl') {
        $png = Join-Path $Work "dlg-$dlg-$lang.png"
        $p = Start-Process -FilePath $Exe -ArgumentList "/lang:$lang /dialog:$dlg /screenshot:`"$png`"" -Wait -PassThru
        Check ($p.ExitCode -eq 0 -and (Test-Path $png) -and (Get-Item $png).Length -gt 8000) "dialog $dlg $lang"
    }
}

# ---- 10. the window renders in both languages
foreach ($lang in 'en', 'nl') {
    $png = Join-Path $Work "win-$lang.png"
    $p = Start-Process -FilePath $Exe -ArgumentList "/lang:$lang /screenshot:`"$png`"" -Wait -PassThru
    Check ($p.ExitCode -eq 0 -and (Test-Path $png) -and (Get-Item $png).Length -gt 15000) "screenshot $lang"
}

Remove-Item $env:CPDECK_PLUGINS_DIR -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ("{0} checks passed, {1} failed (scratch files in {2})" -f $pass, $fail, $Work)
if ($fail -gt 0) { exit 1 }
