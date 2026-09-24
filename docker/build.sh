#!/usr/bin/env bash
# Container entrypoint. Mirrors .github/workflows/release.yml:
#   1. decode KEYSTORE_BASE64 -> app/release.keystore (if set)
#   2. ./gradlew assembleRelease   (or assembleDebug, or the `check` task set)
#   3. copy the APK to /dist and print its signer
#
# The repo is mounted read-only at /src-ro; we copy what git would commit into /src so the
# host's build/ and .gradle/ directories never mix with the container build.
set -euo pipefail

variant="${1:-release}"
case "$variant" in
  release) tasks=(assembleRelease); out=app/build/outputs/apk/release ;;
  debug)   tasks=(assembleDebug);   out=app/build/outputs/apk/debug ;;
  check)   tasks=(ktlintCheck testDebugUnitTest assembleDebug); out=app/build/outputs/apk/debug ;;
  *) echo "usage: build-apk [release|debug|check]" >&2; exit 2 ;;
esac

echo "==> Copying sources"
if git -C /src-ro -c safe.directory='*' ls-files -z -co --exclude-standard > /tmp/files.z 2>/dev/null; then
  (cd /src-ro && tar --null -T /tmp/files.z -cf - | tar -C /src -xf -)
else
  echo "    (git unavailable in this checkout, falling back to tar with excludes)"
  tar -C /src-ro \
      --exclude=./.git --exclude=./.gradle --exclude=./.idea --exclude=./.claude \
      --exclude=./build --exclude=./app/build --exclude=./dist --exclude=./local.properties \
      -cf - . | tar -C /src -xf -
fi
chmod +x /src/gradlew
# Windows checkouts with core.autocrlf=true hand us CRLF scripts; /bin/sh needs LF.
sed -i 's/\r$//' /src/gradlew /src/gradle/wrapper/gradle-wrapper.properties

if [ -n "${KEYSTORE_BASE64:-}" ]; then
  echo "==> Decoding release keystore from KEYSTORE_BASE64"
  echo "$KEYSTORE_BASE64" | base64 -d > /src/app/release.keystore
  for v in KEYSTORE_PASSWORD KEY_ALIAS KEY_PASSWORD; do
    [ -n "${!v:-}" ] || echo "    WARNING: $v is not set; signing will fail or fall back" >&2
  done
elif [ "$variant" = release ]; then
  echo "==> No KEYSTORE_BASE64 set: building release without the release keystore" >&2
  echo "    (put KEYSTORE_BASE64/KEYSTORE_PASSWORD/KEY_ALIAS/KEY_PASSWORD in docker/release.env)" >&2
fi

echo "==> ./gradlew ${tasks[*]}"
cd /src
./gradlew --no-daemon --console=plain "${tasks[@]}"

if [ "$variant" = check ]; then
  echo "==> Copying test reports to /dist/reports"
  rm -rf /dist/reports && mkdir -p /dist/reports
  cp -r app/build/reports/tests /dist/reports/ 2>/dev/null || true
  cp -r app/build/reports/ktlint /dist/reports/ 2>/dev/null || true
fi

echo "==> Collecting APK(s)"
mkdir -p /dist
cp -v "$out"/*.apk /dist/
for apk in /dist/*.apk; do
  echo "--- $(basename "$apk")"
  "$ANDROID_HOME"/build-tools/*/apksigner verify --print-certs "$apk" \
    | grep -E 'certificate DN|SHA-256 digest' || true
done
