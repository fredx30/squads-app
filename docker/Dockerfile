# Reproduces the GitHub "Build Release APK" workflow locally:
# Ubuntu + Eclipse Temurin JDK 21 + Android SDK, then ./gradlew assembleRelease.
# Build once:   docker build -t squads-android-build:local docker/
# Then use:     docker/build-apk.ps1   (or `just docker-release`)
FROM eclipse-temurin:21-jdk-jammy

ARG ANDROID_CMDLINE_TOOLS=13114758
ARG ANDROID_PLATFORM=36
ARG ANDROID_BUILD_TOOLS=36.0.0

ENV ANDROID_HOME=/opt/android-sdk \
    ANDROID_SDK_ROOT=/opt/android-sdk \
    GRADLE_USER_HOME=/gradle-cache \
    GRADLE_OPTS="-Dorg.gradle.daemon=false" \
    DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl unzip git \
    && rm -rf /var/lib/apt/lists/*

# Optional corporate TLS-inspection root CA(s). Drop PEM files as docker/certs/*.crt
# (gitignored). They are trusted by both the OS bundle (curl, sdkmanager) and the JDK
# (Gradle). Without them, Maven Central fails with "PKIX path building failed" on
# networks that intercept TLS.
COPY certs/ /tmp/certs/
RUN set -eu; found=0; \
    for c in /tmp/certs/*.crt; do \
        [ -f "$c" ] || continue; found=1; \
        cp "$c" "/usr/local/share/ca-certificates/$(basename "$c")"; \
        keytool -importcert -noprompt -cacerts -storepass changeit \
            -alias "$(basename "$c" .crt)" -file "$c"; \
    done; \
    if [ "$found" = 1 ]; then update-ca-certificates; fi; \
    rm -rf /tmp/certs

# Android SDK: command-line tools, then the platform and build-tools the app compiles against.
RUN mkdir -p "$ANDROID_HOME/cmdline-tools" \
    && curl -fsSL -o /tmp/cmdline-tools.zip \
        "https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_CMDLINE_TOOLS}_latest.zip" \
    && unzip -q /tmp/cmdline-tools.zip -d /tmp/cmdline-tools \
    && mv /tmp/cmdline-tools/cmdline-tools "$ANDROID_HOME/cmdline-tools/latest" \
    && rm -rf /tmp/cmdline-tools /tmp/cmdline-tools.zip
ENV PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"
RUN yes | sdkmanager --licenses > /dev/null \
    && sdkmanager --install "platform-tools" \
        "platforms;android-${ANDROID_PLATFORM}" \
        "build-tools;${ANDROID_BUILD_TOOLS}"

COPY build.sh /usr/local/bin/build-apk
RUN chmod +x /usr/local/bin/build-apk

WORKDIR /src
VOLUME ["/gradle-cache"]
ENTRYPOINT ["/usr/local/bin/build-apk"]
CMD ["release"]
