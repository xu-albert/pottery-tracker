import java.util.Properties

plugins {
    id("com.android.application")
    // Firebase. google-services generates the resources the SDKs read at runtime;
    // crashlytics uploads R8 mapping files so release stack traces are readable;
    // firebase-perf adds the automatic network/trace instrumentation.
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
    id("com.google.firebase.firebase-perf")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing is configured from android/key.properties, which is gitignored and
// never committed. See docs/android-release.md for how to generate the upload keystore.
//
// Without that file the build falls back to the Android debug key so a clean checkout
// still builds. That fallback is a developer convenience, not a shippable state: pass
// -PrequireReleaseSigning=true (or set POTTER_JOURNAL_REQUIRE_RELEASE_SIGNING=1) for any
// artifact destined for Play, and the build fails instead of silently producing a
// debug-signed upload candidate.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties =
    Properties().apply {
        if (keystorePropertiesFile.exists()) {
            keystorePropertiesFile.inputStream().use { load(it) }
        }
    }

val requiredSigningKeys = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
val missingSigningKeys =
    requiredSigningKeys.filter { keystoreProperties.getProperty(it).isNullOrBlank() }
val hasReleaseSigning = keystorePropertiesFile.exists() && missingSigningKeys.isEmpty()

val releaseSigningRequired =
    project.findProperty("requireReleaseSigning")?.toString().toBoolean() ||
        System.getenv("POTTER_JOURNAL_REQUIRE_RELEASE_SIGNING") == "1"

// A key.properties that exists but is incomplete is always an error — it is a
// misconfiguration, never an intentional state, and silently falling back would hide it.
if (keystorePropertiesFile.exists() && missingSigningKeys.isNotEmpty()) {
    throw GradleException(
        "android/key.properties is missing or has blank values for: " +
            "${missingSigningKeys.joinToString(", ")}. " +
            "See docs/android-release.md section 2.",
    )
}

if (!hasReleaseSigning) {
    if (releaseSigningRequired) {
        throw GradleException(
            "Release signing was required but android/key.properties does not exist. " +
                "See docs/android-release.md section 2 to generate the upload keystore.",
        )
    }
    logger.warn(
        "WARNING: android/key.properties not found — release builds will be signed with the " +
            "Android debug key. Google Play rejects debug-signed uploads. See " +
            "docs/android-release.md section 2.",
    )
}

android {
    namespace = "com.potterytracker.pottery_tracker"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // Permanent once the app is published — it can never be changed for the life of the
        // Play listing, and it must keep matching `package_name` in google-services.json and
        // the Firebase Android app registration.
        applicationId = "com.potterytracker.pottery_tracker"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                // rootProject, not project: a relative storeFile should resolve against
                // android/ (where key.properties lives), not android/app/.
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                // v1 (JAR signing) is unnecessary at minSdk 24 and only adds weight.
                // v3 is what supports signing-key rotation later, so it is worth having.
                enableV1Signing = false
                enableV2Signing = true
                enableV3Signing = true
            }
        }
    }

    buildTypes {
        release {
            signingConfig =
                if (hasReleaseSigning) {
                    signingConfigs.getByName("release")
                } else {
                    signingConfigs.getByName("debug")
                }
        }
    }
}

flutter {
    source = "../.."
}
