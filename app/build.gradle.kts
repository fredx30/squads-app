import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
    id("com.google.dagger.hilt.android")
    id("com.google.devtools.ksp")
    id("org.jetbrains.kotlin.plugin.serialization")
}

// Release signing. Values come from the environment first (CI), then local.properties.
// Blank values count as unset: GitHub Actions passes "" for a missing secret.
// Nothing here throws at configuration time, so debug builds, unit tests, ktlint and
// IDE sync keep working without a keystore; release packaging fails instead (see
// verifyReleaseSigning below the android block).
val releaseKeystore = file("release.keystore")
val localProperties =
    Properties().apply {
        val localPropsFile = rootProject.file("local.properties")
        if (localPropsFile.exists()) localPropsFile.inputStream().use { load(it) }
    }

fun signingValue(name: String): String? =
    System.getenv(name)?.takeIf { it.isNotBlank() }
        ?: localProperties.getProperty(name)?.takeIf { it.isNotBlank() }

val releaseStorePassword = signingValue("KEYSTORE_PASSWORD")
val releaseKeyAlias = signingValue("KEY_ALIAS")
val releaseKeyPassword = signingValue("KEY_PASSWORD")

val releaseSigningProblems: List<String> =
    buildList {
        if (!releaseKeystore.exists()) add("keystore file not found at ${releaseKeystore.path}")
        if (releaseStorePassword == null) add("KEYSTORE_PASSWORD is not set")
        if (releaseKeyAlias == null) add("KEY_ALIAS is not set")
        if (releaseKeyPassword == null) add("KEY_PASSWORD is not set")
    }
val isReleaseSigningConfigured = releaseSigningProblems.isEmpty()

android {
    namespace = "com.squads.app"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.squads.app"
        minSdk = 26
        targetSdk = 35
        versionCode = 8
        versionName = "0.4.1"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    signingConfigs {
        if (isReleaseSigningConfigured) {
            create("release") {
                storeFile = releaseKeystore
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        debug {
            // Always the default debug keystore: the .dev app never carries the production signer.
            applicationIdSuffix = ".dev"
        }
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            // No debug-key fallback. Without a complete release config the variant stays
            // unsigned and verifyReleaseSigning fails release packaging with a clear message.
            if (isReleaseSigningConfigured) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
    }

    buildFeatures {
        compose = true
    }

    @Suppress("UnstableApiUsage")
    testOptions {
        unitTests.all {
            it.useJUnitPlatform()
        }
    }
}

// Fails release packaging (assembleRelease / bundleRelease) when signing is incomplete,
// instead of producing an unsigned or debug-signed "release". The message is computed at
// configuration time so the task action captures only a String (configuration-cache safe).
val verifyReleaseSigning =
    tasks.register("verifyReleaseSigning") {
        group = "verification"
        description = "Fails if the release signing config is incomplete"
        val failureMessage: String? =
            if (isReleaseSigningConfigured) {
                null
            } else {
                "Release signing is not configured:\n" +
                    releaseSigningProblems.joinToString("\n") { "  - $it" } +
                    "\nProvide app/release.keystore and set KEYSTORE_PASSWORD, KEY_ALIAS and " +
                    "KEY_PASSWORD as environment variables or in local.properties, or run the " +
                    "'Setup signing keys' GitHub workflow to create placeholder secrets for CI."
            }
        doFirst {
            if (failureMessage != null) throw GradleException(failureMessage)
        }
    }

val releasePackagingTasks = setOf("packageRelease", "packageReleaseBundle", "signReleaseBundle")
tasks.configureEach {
    if (name in releasePackagingTasks) dependsOn(verifyReleaseSigning)
}

dependencies {
    // Compose BOM — single version for all Compose libs
    val composeBom = platform("androidx.compose:compose-bom:2026.03.01")
    implementation(composeBom)

    // Compose UI
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3:1.5.0-alpha16")
    implementation("androidx.compose.material:material-icons-extended")

    // Activity & Navigation
    implementation("androidx.activity:activity-compose:1.13.0")
    implementation("androidx.navigation3:navigation3-runtime:1.1.0-rc01")
    implementation("androidx.navigation3:navigation3-ui:1.1.0-rc01")
    implementation("androidx.lifecycle:lifecycle-viewmodel-navigation3:2.11.0-alpha03")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-core:1.10.0")

    // Lifecycle & ViewModel
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.10.0")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.10.0")

    // Hilt DI
    implementation("com.google.dagger:hilt-android:2.59.2")
    ksp("com.google.dagger:hilt-android-compiler:2.59.2")
    implementation("androidx.hilt:hilt-navigation-compose:1.3.0")

    // Google Fonts for Compose (Inter font)
    implementation("androidx.compose.ui:ui-text-google-fonts")

    // Haze (glassmorphism / blur effects)
    implementation("dev.chrisbanes.haze:haze:1.7.2")
    implementation("dev.chrisbanes.haze:haze-materials:1.7.2")

    // HTTP client
    implementation("com.squareup.okhttp3:okhttp:5.3.2")

    // Image loading (Coil 3)
    implementation("io.coil-kt.coil3:coil-compose:3.4.0")
    implementation("io.coil-kt.coil3:coil-network-okhttp:3.4.0")

    // Room database
    val roomVersion = "2.8.4"
    implementation("androidx.room:room-runtime:$roomVersion")
    implementation("androidx.room:room-ktx:$roomVersion")
    ksp("androidx.room:room-compiler:$roomVersion")

    // HTML parsing
    implementation("org.jsoup:jsoup:1.22.1")

    // Browser (CustomTab for OAuth)
    implementation("androidx.browser:browser:1.10.0")

    // Baseline profile installer
    implementation("androidx.profileinstaller:profileinstaller:1.4.1")

    // Splash screen
    implementation("androidx.core:core-ktx:1.18.0")
    implementation("androidx.core:core-splashscreen:1.2.0")

    // Testing
    testImplementation("org.junit.jupiter:junit-jupiter:6.0.3")
    testRuntimeOnly("org.junit.platform:junit-platform-launcher")
    testImplementation("org.json:json:20240303")
    androidTestImplementation(composeBom)
    androidTestImplementation("androidx.compose.ui:ui-test-junit4")
    debugImplementation("androidx.compose.ui:ui-tooling")
    debugImplementation("androidx.compose.ui:ui-test-manifest")
}
