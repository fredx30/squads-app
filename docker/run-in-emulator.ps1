<#
.SYNOPSIS
  Install the APK from dist/ on an Android emulator and launch the app.
.DESCRIPTION
  First run bootstraps what is missing: Android command-line tools, the API 36 x86_64
  system image (~1.5 GB download), and an AVD named squads_api36. Then it boots the
  emulator if no device is online, installs the APK and starts MainActivity. An already
  online device (emulator or USB) is used as is; nothing is downloaded in that case.
.PARAMETER Variant
  release (default) installs dist/app-release.apk as com.squads.app;
  debug installs dist/app-debug.apk as com.squads.app.dev.
.PARAMETER Build
  Run docker/build-apk.ps1 first so the APK is fresh.
#>
[CmdletBinding()]
param(
    [ValidateSet('release', 'debug')]
    [string]$Variant = 'release',
    [switch]$Build,
    [string]$AvdName = 'squads_api36',
    [string]$SystemImage = 'system-images;android-36;google_apis;x86_64',
    [string]$Device = 'pixel_7'
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$sdk = if ($env:ANDROID_HOME) { $env:ANDROID_HOME }
    elseif ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT }
    else { "$env:LOCALAPPDATA\Android\Sdk" }
$adb = "$sdk\platform-tools\adb.exe"
$emulator = "$sdk\emulator\emulator.exe"
$sdkmanager = "$sdk\cmdline-tools\latest\bin\sdkmanager.bat"
$avdmanager = "$sdk\cmdline-tools\latest\bin\avdmanager.bat"

if ($Build) { & "$PSScriptRoot\build-apk.ps1" -Variant $Variant }

$apk = Join-Path $repo "dist\app-$Variant.apk"
if (-not (Test-Path $apk)) {
    $fallback = Join-Path $repo "app\build\outputs\apk\$Variant\app-$Variant.apk"
    if (Test-Path $fallback) { $apk = $fallback }
    else { throw "No APK at $apk. Run docker/build-apk.ps1 -Variant $Variant first (or pass -Build)." }
}
$package = if ($Variant -eq 'debug') { 'com.squads.app.dev' } else { 'com.squads.app' }

foreach ($p in @($adb, $emulator)) {
    if (-not (Test-Path $p)) {
        throw "Missing $p. Install the Android SDK platform-tools and emulator (Android Studio > SDK Manager)."
    }
}

# JDK for sdkmanager/avdmanager: prefer JAVA_HOME, else Android Studio's bundled JBR.
if (-not $env:JAVA_HOME) {
    $jbr = "$env:LOCALAPPDATA\Programs\Android Studio\jbr"
    if (Test-Path "$jbr\bin\java.exe") { $env:JAVA_HOME = $jbr }
}

# --- 1. use whatever is already online; otherwise bootstrap tools + image + AVD and boot it ---
& $adb start-server | Out-Null
$online = @(& $adb devices | Select-String '\tdevice$')
if ($online) {
    Write-Host "==> Using online device $(($online[0].Line -split '\t')[0])" -ForegroundColor Cyan
} else {
    # --- 1a. command-line tools ----------------------------------------------------------
    if (-not (Test-Path $sdkmanager)) {
        Write-Host '==> Installing Android command-line tools' -ForegroundColor Cyan
        $zip = Join-Path $env:TEMP 'commandlinetools-win.zip'
        $tmp = Join-Path $env:TEMP 'commandlinetools-win'
        Invoke-WebRequest -Uri 'https://dl.google.com/android/repository/commandlinetools-win-13114758_latest.zip' `
            -OutFile $zip -UseBasicParsing
        if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
        Expand-Archive -Path $zip -DestinationPath $tmp
        New-Item -ItemType Directory -Force "$sdk\cmdline-tools" | Out-Null
        Move-Item "$tmp\cmdline-tools" "$sdk\cmdline-tools\latest"
        Remove-Item -Recurse -Force $tmp, $zip
    }

    # --- 1b. system image + AVD ----------------------------------------------------------
    $avds = @(& $emulator -list-avds 2>$null)
    if ($avds -notcontains $AvdName) {
        Write-Host "==> Installing $SystemImage (large download, once)" -ForegroundColor Cyan
        ('y' * 20).ToCharArray() | ForEach-Object { "$_" } | & $sdkmanager --licenses | Out-Null
        & $sdkmanager --install $SystemImage 'platform-tools' 'emulator'
        if ($LASTEXITCODE -ne 0) { throw 'sdkmanager failed.' }
        Write-Host "==> Creating AVD $AvdName ($Device)" -ForegroundColor Cyan
        'no' | & $avdmanager create avd --force --name $AvdName --package $SystemImage --device $Device
        if ($LASTEXITCODE -ne 0) { throw 'avdmanager failed.' }
    }

    # --- 1c. boot emulator ---------------------------------------------------------------
    Write-Host "==> Starting emulator $AvdName" -ForegroundColor Cyan
    Start-Process -FilePath $emulator -WindowStyle Minimized `
        -ArgumentList @('-avd', $AvdName, '-netdelay', 'none', '-netspeed', 'full')
    & $adb wait-for-device
    $deadline = (Get-Date).AddMinutes(4)
    do {
        Start-Sleep -Seconds 3
        $booted = (& $adb shell getprop sys.boot_completed 2>$null | Out-String).Trim()
    } until ($booted -eq '1' -or (Get-Date) -gt $deadline)
    if ($booted -ne '1') { throw 'Emulator did not finish booting within 4 minutes.' }
}

# --- 2. install + launch -------------------------------------------------------------
Write-Host "==> Installing $apk" -ForegroundColor Cyan
& $adb install -r -d $apk
if ($LASTEXITCODE -ne 0) {
    Write-Warning "Install failed (signature change?). Uninstalling $package and retrying."
    & $adb uninstall $package | Out-Null
    & $adb install $apk
    if ($LASTEXITCODE -ne 0) { throw 'adb install failed.' }
}
Write-Host "==> Launching $package" -ForegroundColor Cyan
& $adb shell am start -n "$package/com.squads.app.MainActivity"
