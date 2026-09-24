<#
.SYNOPSIS
  Build the Squads APK inside Docker, the same way the GitHub release workflow does.
.DESCRIPTION
  Builds the squads-android-build:local image on first use (or with -Rebuild), then runs
  ./gradlew assembleRelease (or assembleDebug) in a container with Temurin JDK 21 and the
  Android SDK. The APK lands in <repo>/dist/. Gradle's cache lives in the named volume
  squads-gradle-cache so repeat builds are fast.

  Signing: create docker/release.env from docker/release.env.example to sign with the
  release keystore exactly like CI. Corporate TLS root CAs go in docker/certs/*.crt.
.EXAMPLE
  ./docker/build-apk.ps1                 # release APK -> dist/app-release.apk
  ./docker/build-apk.ps1 -Variant debug  # debug APK   -> dist/app-debug.apk
  ./docker/build-apk.ps1 -Variant check  # ktlintCheck + unit tests + debug APK; reports in dist/reports
#>
[CmdletBinding()]
param(
    [ValidateSet('release', 'debug', 'check')]
    [string]$Variant = 'release',
    [switch]$Rebuild
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$image = 'squads-android-build:local'

docker version --format '{{.Server.Version}}' > $null 2>&1
if ($LASTEXITCODE -ne 0) {
    throw 'Docker daemon is not reachable. Start Rancher Desktop (container engine: dockerd/moby) and retry.'
}

$certs = Get-ChildItem "$repo/docker/certs" -Filter *.crt -ErrorAction SilentlyContinue
if (-not $certs) {
    Write-Warning 'No docker/certs/*.crt found. On a network with TLS inspection, dependency downloads will fail with "PKIX path building failed". Export the root CA to docker/certs/ and run with -Rebuild.'
}

docker image inspect $image > $null 2>&1
if ($Rebuild -or $LASTEXITCODE -ne 0) {
    Write-Host "==> Building image $image" -ForegroundColor Cyan
    docker build -t $image "$repo/docker"
    if ($LASTEXITCODE -ne 0) { throw 'Image build failed.' }
}

New-Item -ItemType Directory -Force "$repo/dist" | Out-Null

$runArgs = @(
    'run', '--rm',
    '-v', "${repo}:/src-ro:ro",
    '-v', "${repo}/dist:/dist",
    '-v', 'squads-gradle-cache:/gradle-cache'
)
$envFile = Join-Path $repo 'docker/release.env'
if (Test-Path $envFile) {
    $runArgs += @('--env-file', $envFile)
} elseif ($Variant -eq 'release') {
    Write-Warning 'docker/release.env not found: release APK will not be signed with the release keystore.'
}
$runArgs += @($image, $Variant)

Write-Host "==> docker $($runArgs -join ' ')" -ForegroundColor Cyan
& docker @runArgs
if ($LASTEXITCODE -ne 0) { throw "Container build failed (exit $LASTEXITCODE)." }

Write-Host "==> APK(s) in $repo\dist" -ForegroundColor Green
Get-ChildItem "$repo/dist" -Filter *.apk | Format-Table Name, Length, LastWriteTime -AutoSize
