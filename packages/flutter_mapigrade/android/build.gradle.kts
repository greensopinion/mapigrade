// The Android part of the plugin (design D57): the Kotlin plugin class, and
// libflutter_mapigrade.so, built with CMake from src/core/ and
// src/main/cpp/. The library links the MapLibre Native FFI preset
// android-arm64-egl, which scripts/build_maplibre_ffi.sh installs into
// third_party/maplibre-native-ffi/ at the repository root, and the APK carries
// both libraries and the FFI's rustls-platform-verifier Android component.
group = "com.greensopinion.flutter_mapigrade"
version = "1.0-SNAPSHOT"

buildscript {
    val kotlinVersion = "2.4.0"
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        classpath("com.android.tools.build:gradle:9.1.0")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
    }
}

val repositoryRoot = projectDir.resolve("../../..").canonicalFile
val ffiDir = repositoryRoot.resolve("third_party/maplibre-native-ffi")
val ffiPresetDir = ffiDir.resolve("android-arm64-egl")
// The verifier's version in the Maven repository is the first 12 characters of
// the FFI commit (see scripts/build_maplibre_ffi.sh).
val ffiCommit =
    repositoryRoot.resolve("scripts/maplibre_ffi.lock").readLines()
        .first { it.startsWith("MAPLIBRE_FFI_COMMIT=") }
        .substringAfter("=")
val verifierVersion = ffiCommit.take(12)

// The application resolves the plugin's dependencies with its own
// repositories, so the FFI's Maven repository is added to every project of
// the build.
rootProject.allprojects {
    repositories {
        google()
        mavenCentral()
        maven { url = uri(ffiDir.resolve("android-maven")) }
    }
}

plugins {
    id("com.android.library")
}

android {
    namespace = "com.greensopinion.flutter_mapigrade"

    compileSdk = 36
    ndkVersion = "30.0.16248370"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
        }
    }

    defaultConfig {
        minSdk = 29
        consumerProguardFiles("consumer-rules.pro")
        ndk {
            abiFilters += "arm64-v8a"
        }
        externalNativeBuild {
            cmake {
                arguments += listOf(
                    "-DANDROID_STL=c++_static",
                    "-DMLN_FFI_DIR=${ffiPresetDir.absolutePath}",
                )
            }
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

// Packages the FFI library through jniLibs, in the per-ABI layout jniLibs
// expects.
abstract class CopyFfiLibrary : DefaultTask() {
    @get:InputFile
    abstract val library: RegularFileProperty

    @get:OutputDirectory
    abstract val outputDirectory: DirectoryProperty

    @TaskAction
    fun copy() {
        val abiDirectory = outputDirectory.get().asFile.resolve("arm64-v8a")
        abiDirectory.deleteRecursively()
        abiDirectory.mkdirs()
        val source = library.get().asFile
        source.copyTo(abiDirectory.resolve(source.name))
    }
}

val copyMapLibreNativeFfi = tasks.register<CopyFfiLibrary>("copyMapLibreNativeFfi") {
    // Missing until `scripts/build_maplibre_ffi.sh android-arm64-egl` has run.
    library.set(ffiPresetDir.resolve("lib/libmaplibre-native-c.so"))
}

androidComponents {
    onVariants { variant ->
        variant.sources.jniLibs?.addGeneratedSourceDirectory(
            copyMapLibreNativeFfi, CopyFfiLibrary::outputDirectory)
    }
}

dependencies {
    implementation("org.maplibre.nativeffi:rustls-platform-verifier-android:$verifierVersion")
}
