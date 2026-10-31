plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Firebase config: put google-services.json in android/app/ (not needed for AUTH_MODE=dev builds).
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

android {
    namespace = "com.companion.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    buildFeatures {
        buildConfig = true
    }

    defaultConfig {
        applicationId = "com.companion.app"
        minSdk = 23 // firebase_auth
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    flavorDimensions += "distribution"
    productFlavors {
        // Sideloaded hackathon/demo build: includes the Tier 2 Accessibility Service.
        create("demo") {
            dimension = "distribution"
            applicationIdSuffix = ".demo"
            buildConfigField("boolean", "TIER2_ENABLED", "true")
            manifestPlaceholders["usesCleartextTraffic"] = "true" // local backend over http during the demo
        }
        // Publishable build: Tier 1 intents only, no Accessibility Service (PRD F10 compliance note).
        create("play") {
            dimension = "distribution"
            buildConfigField("boolean", "TIER2_ENABLED", "false")
            manifestPlaceholders["usesCleartextTraffic"] = "false"
        }
    }

    buildTypes {
        release {
            // Use your own signing config for a real release.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
}

flutter {
    source = "../.."
}
