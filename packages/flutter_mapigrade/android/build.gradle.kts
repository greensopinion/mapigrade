// The Android part of the plugin (design D57): the Kotlin plugin class, and
// libflutter_mapigrade.so, built with CMake from src/core/ and
// src/main/cpp/, linked against the MapLibre Native FFI library
// libmaplibre-native-c.so.
//
// The FFI comes from one of two places (design D100 and D103 of the
// publish-readiness change):
//
// - Release mode: the runtime AAR of the FFI release in ../maplibre_ffi.lock,
//   from Maven Central. The AAR gives the APK the library for arm64-v8a,
//   armeabi-v7a and x86_64, the rustls-platform-verifier classes and their keep
//   rules. CMake finds the library and its headers through the AAR's Prefab
//   module maplibre-native-c.
// - Local mode, when the Gradle property mapigrade.ffiDir names an existing
//   directory: the output of scripts/build_maplibre_ffi.sh in that directory,
//   for the ABIs of the Android presets it installed. The plugin packages the
//   library itself and depends on the verifier from the local Maven repository
//   that the script installs. The example and the test harness set the property
//   in their android/gradle.properties.
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

val ffiLock = projectDir.resolve("../../../packages/flutter_mapigrade/maplibre_ffi.lock").readLines()
fun ffiLockValue(key: String) =
    ffiLock.first { it.startsWith("$key=") }.substringAfter("=")
val ffiVersion = ffiLockValue("MAPLIBRE_FFI_VERSION")
val ffiRuntime =
    "org.maplibre.nativeffi:maplibre-native-ffi-runtime-opengl-android:$ffiVersion"

// The FFI's Android presets and the ABI each one builds.
val ffiPresetAbis = mapOf(
    "android-arm64-egl" to "arm64-v8a",
    "android-arm-egl" to "armeabi-v7a",
    "android-x64-egl" to "x86_64",
)
val releaseAbis = listOf("arm64-v8a", "armeabi-v7a", "x86_64")

// A relative mapigrade.ffiDir is relative to the application's android/
// directory, which holds its gradle.properties.
val localFfiDir: File? =
    (findProperty("mapigrade.ffiDir") as String?)
        ?.let { rootProject.projectDir.resolve(it).canonicalFile }
        ?.takeIf { it.isDirectory }
// The installed Android presets, by ABI.
val localPresets: Map<String, File> =
    if (localFfiDir == null) {
        emptyMap()
    } else {
        ffiPresetAbis
            .map { (preset, abi) -> abi to localFfiDir.resolve(preset) }
            .filter { (_, dir) -> dir.resolve("lib/libmaplibre-native-c.so").isFile }
            .toMap()
    }
if (localFfiDir != null) {
    check(localPresets.isNotEmpty()) {
        "mapigrade.ffiDir ($localFfiDir) has no Android preset; run scripts/build_maplibre_ffi.sh android-arm64-egl"
    }
    logger.lifecycle(
        "flutter_mapigrade: MapLibre Native FFI local build in $localFfiDir, ABIs ${localPresets.keys.joinToString()}")
} else {
    logger.lifecycle("flutter_mapigrade: MapLibre Native FFI $ffiVersion from Maven Central")
}
val abis = if (localFfiDir != null) localPresets.keys.toList() else releaseAbis

repositories {
    google()
    mavenCentral()
}

// The application resolves the plugin's dependencies with its own
// repositories, so in local mode the FFI's Maven repository is added to every
// project of the build.
if (localFfiDir != null) {
    rootProject.allprojects {
        repositories {
            maven { url = uri(localFfiDir.resolve("android-maven")) }
        }
    }
}

plugins {
    id("com.android.library")
}

// In local mode, the directory that holds <abi>/libmaplibre-native-c.so, which
// CMake links against and the plugin packages through jniLibs.
val ffiLibraryDir = layout.buildDirectory.dir("ffi-lib")

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

    // Release mode: CMake finds the FFI through the runtime AAR's Prefab module.
    buildFeatures {
        prefab = localFfiDir == null
    }

    defaultConfig {
        minSdk = 29
        consumerProguardFiles("consumer-rules.pro")
        ndk {
            abiFilters += abis
        }
        externalNativeBuild {
            cmake {
                arguments += "-DANDROID_STL=c++_static"
                localPresets.values.firstOrNull()?.let { preset ->
                    arguments += listOf(
                        "-DMLN_FFI_LIBRARY_DIR=${ffiLibraryDir.get().asFile.absolutePath}",
                        "-DMLN_FFI_INCLUDE_DIR=${preset.resolve("include").absolutePath}",
                    )
                }
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

// Copies libmaplibre-native-c.so of each local preset into
// outputDirectory/<abi>/, the layout that jniLibs and CMake expect.
abstract class CopyFfiLibrary : DefaultTask() {
    @get:Input
    abstract val abis: ListProperty<String>

    // The libraries, in the order of abis.
    @get:InputFiles
    abstract val libraries: ConfigurableFileCollection

    @get:OutputDirectory
    abstract val outputDirectory: DirectoryProperty

    @TaskAction
    fun copy() {
        val output = outputDirectory.get().asFile
        output.deleteRecursively()
        abis.get().zip(libraries.files.toList()).forEach { (abi, library) ->
            library.copyTo(output.resolve(abi).resolve(library.name))
        }
    }
}

if (localFfiDir != null) {
    val copyFfiLibrary = tasks.register<CopyFfiLibrary>("copyMapLibreNativeFfi") {
        abis.set(localPresets.keys.toList())
        libraries.from(localPresets.values.map { it.resolve("lib/libmaplibre-native-c.so") })
        outputDirectory.set(ffiLibraryDir)
    }

    // CMake links against the library, so it must be in place before any
    // CMake task of any variant and ABI.
    tasks.configureEach {
        if (name.startsWith("configureCMake") || name.startsWith("buildCMake")) {
            dependsOn(copyFfiLibrary)
        }
    }

    androidComponents {
        onVariants { variant ->
            variant.sources.jniLibs?.addGeneratedSourceDirectory(
                copyFfiLibrary, CopyFfiLibrary::outputDirectory)
        }
    }
}

dependencies {
    if (localFfiDir != null) {
        // The verifier's version in the local Maven repository is the first 12
        // characters of the FFI commit (see scripts/build_maplibre_ffi.sh).
        val verifierVersion = ffiLockValue("MAPLIBRE_FFI_COMMIT").take(12)
        implementation("org.maplibre.nativeffi:rustls-platform-verifier-android:$verifierVersion")
    } else {
        implementation(ffiRuntime)
    }
}
