# Builds release\ChasePlane-Deck-Setup.exe: one installer (English + Dutch) with the Stream Deck plugin (and its profiles) and the ChasePlane key list embedded,
# and release\SHA256.txt. The exe is the only file to hand out (plugin, all profiles, hotkeys-only profiles, key list and help are inside it).
# Needs only what Windows ships (csc.exe of .NET Framework 4). Run build\Build-ChasePlaneXL.ps1 first so the plugin package and the key list are current.
# The version comes from the file VERSION in the project root (edit it, rebuild both scripts, publish the new exe).
#
#   -UpdateUrl    address of a small JSON file that announces the newest version, e.g. https://example.com/chaseplane-deck/latest.json
#                 (format: {"version":"1.1.0.0","url":"https://.../ChasePlane-Deck-Setup.exe","notes":"..."}). Without it Setup never uses the network.
#   -DownloadUrl  page or file people download the new version from; needed with -Publish
#   -Publish      copy the exe + SHA256.txt to download\ and write latest.json in the project root (both are committed to the GitHub repo; the repo serves latest.json as the update address)
#   -Notes        short "what is new" text for latest.json
# Run:  powershell -ExecutionPolicy Bypass -File build\Build-Installer.ps1 [-UpdateUrl https://...] [-DownloadUrl https://...] [-Notes "..."]
# Keep this file ASCII-only (Windows PowerShell 5.1 reads BOM-less UTF-8 as ANSI).
param([string]$UpdateUrl = '', [string]$DownloadUrl = '', [string]$Notes = '', [switch]$Publish)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$Root = Split-Path $PSScriptRoot -Parent
$Src = Join-Path $Root 'installer'
$Obj = Join-Path $Src 'obj'
$Out = Join-Path $Root 'release'
$Plugin = Join-Path $Root 'ChasePlane XL.streamDeckPlugin'
$Csv = Join-Path $Root 'chaseplane-keymap.csv'
$Csc = 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe'
foreach ($f in $Plugin, $Csv, $Csc) { if (-not (Test-Path $f)) { throw "Missing: $f" } }
if ($UpdateUrl -and $UpdateUrl -notmatch '^https://') { throw '-UpdateUrl must start with https://' }
if ($DownloadUrl -and $DownloadUrl -notmatch '^https://') { throw '-DownloadUrl must start with https://' }
New-Item -ItemType Directory -Force -Path $Obj, $Out | Out-Null

$Version = [version]((Get-Content (Join-Path $Root 'VERSION') -Raw).Trim())
$Short = '{0}.{1}.{2}' -f $Version.Major, $Version.Minor, [math]::Max($Version.Build, 0)

# the plugin package must carry the same version as the installer
Add-Type -AssemblyName System.IO.Compression.FileSystem
$pz = [System.IO.Compression.ZipFile]::OpenRead($Plugin)
$sr = New-Object System.IO.StreamReader($pz.GetEntry('com.chaseplanexl.deck.sdPlugin/manifest.json').Open()); $pm = $sr.ReadToEnd(); $sr.Close(); $pz.Dispose()
$pv = [regex]::Match($pm, '"Version"\s*:\s*"([0-9.]+)"').Groups[1].Value
if ([version]$pv -ne $Version) { throw "VERSION says $Version but the plugin package has ${pv} - run build\Build-ChasePlaneXL.ps1 first" }

# generated version resource
[System.IO.File]::WriteAllText((Join-Path $Obj 'Version.cs'), "using System.Reflection;`r`n[assembly: AssemblyVersion(`"$Version`")]`r`n[assembly: AssemblyFileVersion(`"$Version`")]`r`n", (New-Object System.Text.UTF8Encoding $false))
[System.IO.File]::WriteAllText((Join-Path $Obj 'update.txt'), $UpdateUrl, (New-Object System.Text.UTF8Encoding $false))

# key list: Command|Keys|Status|InHybrid|Label
$lines = @('# Command|Keys|Status|InHybrid|Label')
foreach ($r in (Import-Csv $Csv)) { $lines += ('{0}|{1}|{2}|{3}|{4}' -f $r.Command, $r.Keys, $r.Status, $r.InHybrid, $r.Button) }
$KeysTxt = Join-Path $Obj 'keys.txt'
[System.IO.File]::WriteAllLines($KeysTxt, $lines, (New-Object System.Text.UTF8Encoding $false))

# names of the ChasePlane profiles (Setup finds them in the Stream Deck app by these exact names) + the hotkeys-only profiles that travel inside the exe
Add-Type -AssemblyName System.IO.Compression
function Get-ProfileName([string]$file) {
    $ms = New-Object System.IO.MemoryStream (, [System.IO.File]::ReadAllBytes($file))
    $z = New-Object System.IO.Compression.ZipArchive($ms)
    $e = $z.Entries | Where-Object { $_.FullName -match '^(Profiles/)?[^/]+\.sdProfile/manifest\.json$' } | Select-Object -First 1
    $sr = New-Object System.IO.StreamReader($e.Open()); $n = ($sr.ReadToEnd() | ConvertFrom-Json).Name; $sr.Close(); $z.Dispose()
    $n
}
$names = @('# exact names of the ChasePlane profiles')
Get-ChildItem (Join-Path $Root 'plugin\com.chaseplanexl.deck.sdPlugin\Profiles') -Filter *.streamDeckProfile -File | ForEach-Object { $names += (Get-ProfileName $_.FullName) }
$HkDir = Join-Path $Root 'hotkeys-only'
$HkTitles = [ordered]@{ Mini = 'Stream Deck Mini'; Standard = 'Stream Deck 15 keys / MK.2 / Scissor Keys'; Neo = 'Stream Deck Neo'; Plus = 'Stream Deck +'; XL = 'Stream Deck XL'; PlusXL = 'Stream Deck + XL'; Studio = 'Stream Deck Studio' }
$hk = @('# File|Title'); $hkResources = @()
foreach ($k in $HkTitles.Keys) {
    $f = Join-Path $HkDir "ChasePlane $k (hotkeys only).streamDeckProfile"
    if (-not (Test-Path $f)) { throw "Missing hotkeys-only profile: $f (run build\Build-ChasePlaneXL.ps1)" }
    $names += (Get-ProfileName $f)
    $hk += "$k|$($HkTitles[$k])"
    $hkResources += "/resource:$f,hk.$k.streamDeckProfile"
}
[System.IO.File]::WriteAllLines((Join-Path $Obj 'profile-names.txt'), @($names | Select-Object -Unique), (New-Object System.Text.UTF8Encoding $false))
[System.IO.File]::WriteAllLines((Join-Path $Obj 'hk.txt'), $hk, (New-Object System.Text.UTF8Encoding $false))

# icon: PNG-compressed .ico (256, 48, 32, 16) from the plugin icon
$srcPng = [System.Drawing.Image]::FromFile((Join-Path $Root 'plugin\com.chaseplanexl.deck.sdPlugin\imgs\plugin\icon@2x.png'))
$sizes = 256, 48, 32, 16; $pngs = @()
foreach ($s in $sizes) {
    $b = New-Object System.Drawing.Bitmap $s, $s, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($b); $g.InterpolationMode = 'HighQualityBicubic'; $g.SmoothingMode = 'HighQuality'; $g.PixelOffsetMode = 'HighQuality'
    $g.DrawImage($srcPng, 0, 0, $s, $s); $g.Dispose()
    $ms = New-Object System.IO.MemoryStream; $b.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png); $pngs += , $ms.ToArray(); $b.Dispose()
}
$srcPng.Dispose()
$ms = New-Object System.IO.MemoryStream; $bw = New-Object System.IO.BinaryWriter $ms
$bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
    $d = if ($sizes[$i] -ge 256) { 0 } else { $sizes[$i] }
    $bw.Write([byte]$d); $bw.Write([byte]$d); $bw.Write([byte]0); $bw.Write([byte]0)
    $bw.Write([uint16]1); $bw.Write([uint16]32); $bw.Write([uint32]$pngs[$i].Length); $bw.Write([uint32]$offset)
    $offset += $pngs[$i].Length
}
foreach ($p in $pngs) { $bw.Write($p) }
$bw.Flush(); $Ico = Join-Path $Obj 'app.ico'; [System.IO.File]::WriteAllBytes($Ico, $ms.ToArray())

$Exe = Join-Path $Out 'ChasePlane-Deck-Setup.exe'
if (Test-Path $Exe) { Remove-Item $Exe -Force }
$cs = @(Get-ChildItem $Src -Filter *.cs -File | ForEach-Object { $_.FullName }) + (Join-Path $Obj 'Version.cs')
$cscArgs = @('/nologo', '/target:winexe', '/optimize+', '/codepage:65001', "/out:$Exe", "/win32icon:$Ico", "/win32manifest:$(Join-Path $Src 'app.manifest')",
             "/resource:$Plugin,plugin.streamDeckPlugin", "/resource:$KeysTxt,keys.txt", "/resource:$(Join-Path $Obj 'update.txt'),update.txt",
             "/resource:$(Join-Path $Obj 'profile-names.txt'),profile-names.txt", "/resource:$(Join-Path $Obj 'hk.txt'),hk.txt",
             '/r:System.dll', '/r:System.Core.dll', '/r:System.Drawing.dll', '/r:System.Windows.Forms.dll', '/r:System.Web.Extensions.dll', '/r:System.IO.Compression.dll') + $hkResources + $cs
& $Csc $cscArgs
if ($LASTEXITCODE -ne 0) { throw "csc failed ($LASTEXITCODE)" }
Write-Host ("Installer: {0} ({1} MB), version {2}{3}" -f $Exe, [math]::Round((Get-Item $Exe).Length / 1MB, 1), $Version, $(if ($UpdateUrl) { ", update check: $UpdateUrl" } else { ', no update address built in' }))

# the exe is the only thing to hand out: plugin, profiles, hotkeys-only profiles, key list and help are inside it
Get-ChildItem $Out -Filter 'ChasePlane-Deck-*.zip' -File | Remove-Item -Force      # older versions of this script also made a zip
$sums = @('{0}  {1}' -f (Get-FileHash $Exe -Algorithm SHA256).Hash, (Split-Path $Exe -Leaf))
[System.IO.File]::WriteAllLines((Join-Path $Out 'SHA256.txt'), $sums, (New-Object System.Text.UTF8Encoding $false))
$sums | ForEach-Object { Write-Host "SHA256   : $_" }

# publish: committed copy of the exe + latest.json (the file the update check reads)
if ($Publish) {
    if (-not $DownloadUrl) { throw '-Publish needs -DownloadUrl' }
    $dl = Join-Path $Root 'download'
    New-Item -ItemType Directory -Force -Path $dl | Out-Null
    Copy-Item $Exe (Join-Path $dl 'ChasePlane-Deck-Setup.exe') -Force
    Copy-Item (Join-Path $Out 'SHA256.txt') (Join-Path $dl 'SHA256.txt') -Force
    $json = ([ordered]@{ version = "$Version"; url = $DownloadUrl; notes = $Notes } | ConvertTo-Json)
    [System.IO.File]::WriteAllText((Join-Path $Root 'latest.json'), $json, (New-Object System.Text.UTF8Encoding $false))
    Write-Host "Published: download\ChasePlane-Deck-Setup.exe + latest.json (version $Version). Commit and push both."
}