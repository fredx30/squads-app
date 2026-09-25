<#
.SYNOPSIS
  Make this machine's Android debug key the one CI uses too.
.DESCRIPTION
  Reuses ~/.android/debug.keystore (what Android Studio and `just run` sign with; created here
  with the standard debug credentials if missing), then stores it as the DEBUG_KEYSTORE_BASE64
  secret on the origin repository with your existing `gh` login. Docker builds mount the same
  file (docker/build-apk.ps1), so IDE, Docker and GitHub debug APKs all install over each other.
  Run once per machine and once per fork; forks inherit no secrets.
.PARAMETER Repo
  owner/name to set the secret on. Defaults to the origin remote (not gh's default repo, which
  may resolve to an upstream remote).
.PARAMETER Replace
  Overwrite an existing DEBUG_KEYSTORE_BASE64 (for example from another machine). Devices with
  a debug build signed by the old key then need an uninstall.
#>
[CmdletBinding()]
param(
    [string]$Repo,
    [switch]$Replace
)
$ErrorActionPreference = 'Stop'
$secretName = 'DEBUG_KEYSTORE_BASE64'
$ks = Join-Path $HOME '.android/debug.keystore'

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw 'gh (GitHub CLI) is not on PATH.' }
gh auth status > $null 2>&1
if ($LASTEXITCODE -ne 0) { throw 'gh is not logged in. Run: gh auth login' }

$keytool = (Get-Command keytool -ErrorAction SilentlyContinue).Source
if (-not $keytool) {
    $keytool = @(
        $(if ($env:JAVA_HOME) { Join-Path $env:JAVA_HOME 'bin/keytool.exe' }),
        (Join-Path $env:LOCALAPPDATA 'Programs/Android Studio/jbr/bin/keytool.exe'),
        'C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe'
    ) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
    if (-not $keytool) { throw 'keytool not found. Set JAVA_HOME or install Android Studio.' }
}

if (-not $Repo) {
    $url = git remote get-url origin
    if ($url -notmatch 'github\.com[:/](?<owner>[^/]+)/(?<name>[^/.]+?)(\.git)?/?$') {
        throw "Cannot parse owner/name from origin '$url'; pass -Repo owner/name."
    }
    $Repo = "$($Matches.owner)/$($Matches.name)"
}

if (-not (Test-Path $ks)) {
    Write-Host "==> Creating $ks" -ForegroundColor Cyan
    New-Item -ItemType Directory -Force (Split-Path -Parent $ks) | Out-Null
    & $keytool -genkeypair -keystore $ks -storepass android -keypass android -alias androiddebugkey `
        -keyalg RSA -keysize 2048 -validity 10950 -dname 'CN=Android Debug, O=Android, C=US'
    if ($LASTEXITCODE -ne 0) { throw 'keytool -genkeypair failed.' }
}
$listing = & $keytool -list -v -keystore $ks -storepass android -alias androiddebugkey 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) { throw "$ks does not open with the standard debug credentials.`n$listing" }
$fp = ([regex]::Match($listing, 'SHA256:\s*([0-9A-F:]+)').Groups[1].Value -replace ':', '').ToLowerInvariant()
if (-not $fp) { throw 'Could not read the certificate fingerprint.' }
Write-Host "==> Debug signer SHA-256: $fp" -ForegroundColor Cyan

$existing = gh secret list -R $Repo --json name -q '.[].name'
if ($LASTEXITCODE -ne 0) { throw "Cannot list secrets on $Repo (need admin on the repo)." }
if (($existing -contains $secretName) -and -not $Replace) {
    Write-Host "==> $secretName already set on $Repo; leaving it. Compare the fingerprint above with a CI debug run's summary; pass -Replace to push this machine's key." -ForegroundColor Yellow
    exit 0
}
[Convert]::ToBase64String([IO.File]::ReadAllBytes($ks)) | gh secret set $secretName -R $Repo
if ($LASTEXITCODE -ne 0) { throw "gh secret set failed for $Repo." }
Write-Host "==> $secretName set on $Repo. CI debug builds now sign with $fp." -ForegroundColor Green
