plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.greensopinion.mapigrade_test_harness"
    compileSdk = flutter.compileSdkVersion
    // The NDK version flutter_mapigrade builds with (design D57).
    ndkVersion = "30.0.16248370"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.greensopinion.mapigrade_test_harness"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // flutter_mapigrade needs API level 29.
        minSdk = 29
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // MapLibre reads PMTiles assets in byte ranges, which needs them stored
    // without compression.
    androidResources {
        noCompress += "pmtiles"
    }

    // With -Pmapigrade.omitNativeLibrary=true, the APK lacks flutter_mapigrade's
    // native library, as on a device without an arm64 ABI, for
    // integration_test/unsupported_test.dart (design D88 of the
    // unsupported-architectures change).
    if (providers.gradleProperty("mapigrade.omitNativeLibrary").orNull == "true") {
        packaging {
            jniLibs {
                excludes += "**/libflutter_mapigrade.so"
            }
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
