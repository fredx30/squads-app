# Local release build (Docker) and emulator launch

Reproduces `.github/workflows/release.yml` on your machine: Ubuntu, Eclipse Temurin JDK 21,
Android SDK, `./gradlew assembleRelease`, with the same `KEYSTORE_*` variables.

| Step | Command | IDE run configuration (`.run/`) |
|---|---|---|
| Build release APK | `./docker/build-apk.ps1` | **Docker - Build Release APK** |
| Build debug APK | `./docker/build-apk.ps1 -Variant debug` | **Docker - Build Debug APK** |
| ktlint + unit tests + debug APK | `./docker/build-apk.ps1 -Variant check` | **Docker - Check (ktlint, tests)** |
| Launch in emulator | `./docker/run-in-emulator.ps1` | **Emulator - Launch Release APK** |
| Build + launch | `./docker/run-in-emulator.ps1 -Build` | **Emulator - Build and Launch Release** |

Output: `dist/app-release.apk` (gitignored). Gradle's cache persists in the Docker volume
`squads-gradle-cache`; `docker volume rm squads-gradle-cache` resets it. Run one build
container at a time: Gradle's cache locking cannot see processes in other containers, so two
builds sharing the volume fail with `Timeout waiting to lock journal cache`. The host script
refuses to start while another build container is running. The same recipes
exist in the `justfile` as `docker-release`, `docker-debug`, `docker-image`, `emulator-run`.

## Prerequisites

- Rancher Desktop with the **dockerd (moby)** engine running.
- PowerShell 7 (`pwsh`). The `.run/` configurations use it, so neither `just` nor Git Bash
  is required.
- For the emulator: Android SDK at `%LOCALAPPDATA%\Android\Sdk` (or `ANDROID_HOME`) with
  `platform-tools` and `emulator`. The script downloads command-line tools, the API 36
  x86_64 system image (~1.5 GB) and creates the `squads_api36` AVD on first use. Allow
  about 6 GB of disk for the image, system image and AVD.

## Corporate networks (TLS inspection)

If dependency downloads fail with `PKIX path building failed`, the network re-signs TLS
with a private root CA. Export it as PEM into `docker/certs/<name>.crt` (gitignored) and
rebuild the image with `./docker/build-apk.ps1 -Rebuild`. From PowerShell:

```powershell
$c = Get-ChildItem Cert:\CurrentUser\Root | Where-Object Subject -eq 'CN=<Your Root CA>' | Select-Object -First 1
$pem = "-----BEGIN CERTIFICATE-----`n" + [Convert]::ToBase64String($c.RawData, 'InsertLineBreaks') + "`n-----END CERTIFICATE-----`n"
Set-Content -Path docker/certs/corp-root.crt -Value $pem -NoNewline
```

## Signing like CI

Copy `docker/release.env.example` to `docker/release.env` (gitignored) and fill in
`KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`. Without it the release
build fails in `verifyReleaseSigning`; there is no fallback key. In CI the same four secrets
come from the *Setup signing keys* workflow (a self-signed placeholder, CN contains
`PLACEHOLDER`) until the real Google Play key is inserted by hand; see the README's Signing
section. The container prints the signer certificate of every APK it produces so you can
compare with a GitHub release (`apksigner verify --print-certs app-release.apk`).

## What differs from CI

- CI builds a clean checkout of the tag. The container copies what `git ls-files` reports
  (tracked plus untracked-but-not-ignored files), so uncommitted edits are included and
  ignored files such as `local.properties` are not.
- CI uses the GitHub runner's preinstalled SDK; the image installs
  `platforms;android-36` and `build-tools;36.0.0`. AGP downloads anything else it needs
  (`android.builder.sdkDownload=true`).

## IDE run configurations

The `.run/*.run.xml` files are IntelliJ *Shell Script* configurations in script-text mode:
each one runs `pwsh -NoProfile -File docker/<script>.ps1 ...` in the IDE terminal with the
project root as working directory, and `pwsh` resolves through `PATH`. They deliberately
leave the interpreter field empty. A filled-in interpreter must be an absolute path to an
existing executable, or the IDE marks the configuration invalid, and an absolute path would
tie the checked-in file to one machine's PowerShell install.
