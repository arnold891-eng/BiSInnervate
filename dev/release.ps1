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

$metadata = @{
    changelog     = $changelog
    changelogType = "markdown"
    displayName   = "$AddonName $version"
    gameVersions  = @($gv.id)
    releaseType   = $Type
} | ConvertTo-Json -Compress

# multipart by hand: Invoke-RestMethod -Form needs PS 6+, this runs on 5.1 too
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

$resp = Invoke-RestMethod -Method Post -Headers $headers -ContentType "multipart/form-data; boundary=$boundary" `
    -Uri "https://wow.curseforge.com/api/projects/$ProjectId/upload-file" -Body $body.ToArray()
Write-Host "uploaded: file id $($resp.id) - $AddonName $version ($Type)"
