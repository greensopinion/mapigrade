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
//   rules. CMake links against the library extracted from the AAR and compiles
//   against the release's headers in src/main/cpp/ffi-include/.
// - Local mode, when the Gradle property mapigrade.ffiDir names an existing
//   directory: the output of scripts/build_maplibre_ffi.sh in that directory,
//   for the ABIs of the Android presets it installed. The plugin packages the
//   library itself and depends on the verifier from the local Maven repository
//   that the script installs. The example and the test harness set the property
//   in their android/gradle.properties.
import javax.inject.Inject

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

val ffiLock = projectDir.resolve("../maplibre_ffi.lock").readLines()
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

// The directory that holds <abi>/libmaplibre-native-c.so, which CMake links
// against. In local mode the plugin also packages it through jniLibs.
val ffiLibraryDir = layout.buildDirectory.dir("ffi-lib")
val ffiIncludeDir =
    localPresets.values.firstOrNull()?.resolve("include")
        ?: projectDir.resolve("src/main/cpp/ffi-include")

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
            abiFilters += abis
        }
        externalNativeBuild {
            cmake {
                arguments += listOf(
                    "-DANDROID_STL=c++_static",
                    "-DMLN_FFI_LIBRARY_DIR=${ffiLibraryDir.get().asFile.absolutePath}",
                    "-DMLN_FFI_INCLUDE_DIR=${ffiIncludeDir.absolutePath}",
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

// Extracts jni/<abi>/libmaplibre-native-c.so of the FFI runtime AAR into
// outputDirectory/<abi>/, for CMake. The APK gets the library from the AAR
// itself.
abstract class ExtractFfiLibrary : DefaultTask() {
    @get:InputFiles
    abstract val aar: ConfigurableFileCollection

    @get:Input
    abstract val abis: ListProperty<String>

    @get:OutputDirectory
    abstract val outputDirectory: DirectoryProperty

    @get:Inject
    abstract val archives: ArchiveOperations

    @get:Inject
    abstract val files: FileSystemOperations

    @TaskAction
    fun extract() {
        files.sync {
            from(archives.zipTree(aar.singleFile)) {
                include(abis.get().map { "jni/$it/libmaplibre-native-c.so" })
                eachFile { path = path.removePrefix("jni/") }
            }
            includeEmptyDirs = false
            into(outputDirectory)
        }
        abis.get().forEach { abi ->
            check(outputDirectory.get().asFile.resolve("$abi/libmaplibre-native-c.so").isFile) {
                "${aar.singleFile.name} has no jni/$abi/libmaplibre-native-c.so"
            }
        }
    }
}

val prepareFfiLibrary =
    if (localFfiDir != null) {
        tasks.register<CopyFfiLibrary>("copyMapLibreNativeFfi") {
            abis.set(localPresets.keys.toList())
            libraries.from(localPresets.values.map { it.resolve("lib/libmaplibre-native-c.so") })
            outputDirectory.set(ffiLibraryDir)
        }
    } else {
        val ffiAar = configurations.detachedConfiguration(dependencies.create("$ffiRuntime@aar"))
        tasks.register<ExtractFfiLibrary>("extractMapLibreNativeFfi") {
            aar.from(ffiAar)
            abis.set(releaseAbis)
            outputDirectory.set(ffiLibraryDir)
        }
    }

// CMake links against the library, so it must be in place before any CMake
// task of any variant and ABI.
tasks.configureEach {
    if (name.startsWith("configureCMake") || name.startsWith("buildCMake")) {
        dependsOn(prepareFfiLibrary)
    }
}

if (localFfiDir != null) {
    androidComponents {
        onVariants { variant ->
            variant.sources.jniLibs?.addGeneratedSourceDirectory(
                prepareFfiLibrary as TaskProvider<CopyFfiLibrary>,
                CopyFfiLibrary::outputDirectory)
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
