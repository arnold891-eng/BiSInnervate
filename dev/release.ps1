# BiS Innervate :: release.ps1
# Zips the addon and pushes it to CurseForge through the upload API.
#
#   .\release.ps1                 -> zip + upload as alpha (nobody is pushed it)
#   .\release.ps1 -Type beta      -> beta; -Type release -> everyone. Or flip it on the dashboard.
#   .\release.ps1 -ZipOnly        -> just the zip, no upload
#
# Needs, once:
#   * the API token in %USERPROFILE%\Downloads\curseforge-token.txt
#     (CurseForge -> My Account -> API Tokens). One line, nothing else.
#   * the project id below (the number on the project's CurseForge page).
#
# The zip lands in Downloads. The changelog sent is the top entry of
# CHANGELOG.md; the version is the TOC's ## Version. Game version is looked
# up live so a client patch never needs a code change here.

param(
    [ValidateSet("release", "beta", "alpha")] [string] $Type = "alpha",
    [switch] $ZipOnly
)

$ErrorActionPreference = "Stop"

$ProjectId = 1674333          # <-- put the CurseForge project id here
$AddonName = "BiSInnervate"
$Root      = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)   # ..\BiSInnervate
$Downloads = Join-Path $env:USERPROFILE "Downloads"
$TokenFile = Join-Path $Downloads "curseforge-token.txt"

# version from the TOC
$toc = Get-Content (Join-Path $Root "$AddonName.toc")
$version = ($toc | Where-Object { $_ -match '^## Version:\s*(.+)$' } | ForEach-Object { $Matches[1].Trim() })
if (-not $version) { throw "no ## Version in the TOC" }

# the top entry of the changelog: from the first "## x.y.z" to the next one
$lines = Get-Content (Join-Path $Root "CHANGELOG.md")
$entry = @(); $inside = $false
foreach ($l in $lines) {
    if ($l -match '^## ') { if ($inside) { break }; $inside = $true; continue }
    if ($inside) { $entry += $l }
}
$changelog = ($entry -join "`n").Trim()

# embedded libs must be byte-identical to their canonical copies, or a release
# ships an old lib (10 Sep 2026: minor 4 still in three addons while minor 5
# fixed the phantom summon). ..\_bisdev\sync.ps1 copies them; -Check just looks.
$canon = @{
    "Libs\LibBiSComm-1.0\LibBiSComm-1.0.lua" = "..\_bisdev\LibBiSComm-1.0\LibBiSComm-1.0.lua"
    "Libs\BiSTheme\Console.lua"              = "..\BiSTheme\Console.lua"
    "Libs\BiSTheme\Options.lua"              = "..\BiSTheme\Options.lua"
}
foreach ($k in $canon.Keys) {
    $mine = Join-Path $Root $k
    $ref  = Join-Path $Root $canon[$k]
    if ((Test-Path $mine) -and (Test-Path $ref)) {
        $a = (Get-FileHash $mine -Algorithm MD5).Hash
        $b = (Get-FileHash $ref  -Algorithm MD5).Hash
        if ($a -ne $b) { throw "embedded $k differs from its canonical copy - run ..\_bisdev\sync.ps1 first" }
    }
}

# the zip: everything but dev/, .pkgmeta and the dot-files
$zip = Join-Path $Downloads "$AddonName-$version.zip"
$stage = Join-Path $env:TEMP "$AddonName-release"
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Path (Join-Path $stage $AddonName) | Out-Null
Get-ChildItem $Root -Force | Where-Object {
    $_.Name -notin @("dev", ".pkgmeta", ".git", ".gitignore", "LICENSE.bak")
} | ForEach-Object { Copy-Item $_.FullName -Destination (Join-Path $stage $AddonName) -Recurse }
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path (Join-Path $stage $AddonName) -DestinationPath $zip
Write-Host "zip: $zip"
if ($ZipOnly) { exit 0 }

if ($ProjectId -eq 0) { throw "set `$ProjectId at the top of this script first" }
if (-not (Test-Path $TokenFile)) { throw "no token file at $TokenFile" }
$token = (Get-Content $TokenFile -Raw).Trim()
$headers = @{ "X-Api-Token" = $token }

# game version: the TBC Classic entry, whatever its id is this month
$types = Invoke-RestMethod -Headers $headers -Uri "https://wow.curseforge.com/api/game/version-types"
$tbcType = $types | Where-Object { $_.name -match 'Burning Crusade|TBC' } | Select-Object -First 1
if (-not $tbcType) { throw "no TBC Classic version type found: " + (($types | ForEach-Object { $_.name }) -join ", ") }
$versions = Invoke-RestMethod -Headers $headers -Uri "https://wow.curseforge.com/api/game/versions"
$gv = $versions | Where-Object { $_.gameVersionTypeID -eq $tbcType.id } | Sort-Object name -Descending | Select-Object -First 1
if (-not $gv) { throw "no game version under type $($tbcType.name)" }
Write-Host "game version: $($gv.name) (id $($gv.id), type $($tbcType.name))"

# multipart by hand: Invoke-RestMethod -Form needs PS 6+, this runs on 5.1 too
function Send-Upload($log, $logType) {
    $metadata = @{
        changelog     = $log
        changelogType = $logType
        displayName   = "$AddonName $version"
        gameVersions  = @($gv.id)
        releaseType   = $Type
    } | ConvertTo-Json -Compress
    $boundary = [System.Guid]::NewGuid().ToString()
    $bytes = [System.IO.File]::ReadAllBytes($zip)
    $enc = [System.Text.Encoding]::UTF8
    $head = "--$boundary`r`nContent-Disposition: form-data; name=`"metadata`"`r`nContent-Type: application/json`r`n`r`n$metadata`r`n" +
            "--$boundary`r`nContent-Disposition: form-data; name=`"file`"; filename=`"$(Split-Path $zip -Leaf)`"`r`nContent-Type: application/zip`r`n`r`n"
    $tail = "`r`n--$boundary--`r`n"
    $body = New-Object System.IO.MemoryStream
    $b = $enc.GetBytes($head); $body.Write($b, 0, $b.Length)
    $body.Write($bytes, 0, $bytes.Length)
    $b = $enc.GetBytes($tail); $body.Write($b, 0, $b.Length)
    return Invoke-RestMethod -Method Post -Headers $headers -ContentType "multipart/form-data; boundary=$boundary" `
        -Uri "https://wow.curseforge.com/api/projects/$ProjectId/upload-file" -Body $body.ToArray()
}

# CurseForge answers 500 now and then for no reason it will name. Three tries
# with the markdown changelog, then once more with it as plain text - if that
# one lands, the markdown was what it choked on and the log will say so.
$resp = $null
$attempts = @(
    @{ log = $changelog; type = "markdown" },
    @{ log = $changelog; type = "markdown" },
    @{ log = $changelog; type = "markdown" },
    @{ log = ($changelog -replace '[`*_]', ''); type = "text" }
)
for ($i = 0; $i -lt $attempts.Count -and -not $resp; $i++) {
    try {
        $resp = Send-Upload $attempts[$i].log $attempts[$i].type
    } catch {
        $msg = $_.Exception.Message
        try { $sr = New-Object IO.StreamReader($_.Exception.Response.GetResponseStream()); $msg = $sr.ReadToEnd() } catch {}
        Write-Host ("attempt {0} ({1}) failed: {2}" -f ($i + 1), $attempts[$i].type, $msg)
        if ($i -lt $attempts.Count - 1) { Start-Sleep -Seconds 5 }
    }
}
if (-not $resp) { throw "upload failed after $($attempts.Count) attempts - the zip is still in Downloads, upload it by hand on the project page" }
Write-Host "uploaded: file id $($resp.id) - $AddonName $version ($Type)"
