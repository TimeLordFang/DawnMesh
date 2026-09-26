import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android plugin.
    id("dev.flutter.flutter-gradle-plugin")
}

// 发布签名从 android/key.properties 读取（该文件不入库）。格式：
//   storeFile=../keystore/dawnmesh.jks   # 相对 android/app/ 或绝对路径
//   storePassword=...
//   keyAlias=...
//   keyPassword=...
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        FileInputStream(keystorePropertiesFile).use { load(it) }
    }
}
fun releaseSigningValue(propertyName: String, environmentName: String): String? =
    keystoreProperties.getProperty(propertyName)?.takeIf { it.isNotBlank() }
        ?: System.getenv(environmentName)?.takeIf { it.isNotBlank() }

val releaseStoreFile = releaseSigningValue("storeFile", "DAWNMESH_KEYSTORE_PATH")
val releaseStorePassword = releaseSigningValue("storePassword", "DAWNMESH_STORE_PASSWORD")
val releaseKeyAlias = releaseSigningValue("keyAlias", "DAWNMESH_KEY_ALIAS")
val releaseKeyPassword = releaseSigningValue("keyPassword", "DAWNMESH_KEY_PASSWORD")
val hasReleaseSigning = listOf(
    releaseStoreFile,
    releaseStorePassword,
    releaseKeyAlias,
    releaseKeyPassword,
).all { !it.isNullOrBlank() }

android {
    // Kotlin namespace 与独立 applicationId 统一使用 DawnMesh 标识。
    namespace = "dev.dawnmesh.intercom"
    compileSdk = 36
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "dev.dawnmesh.intercom"
        // 项目基线是 26；不要用 flutter.minSdkVersion，它会随 Flutter 版本漂移。
        minSdk = 26
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        externalNativeBuild {
            cmake {
                cppFlags += "-std=c++17"
                arguments += "-DANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES=ON"
            }
        }
        ndk {
            // 只出真机会用到的 ABI，x86 模拟器保留 x86_64。
            abiFilters += listOf("arm64-v8a", "armeabi-v7a", "x86_64")
        }
    }

    // native/ 下的 C++（无锁环形缓冲、PCM 混音、帧编解码）此前从未接入构建，
    // 所以 libdawn_mesh_native.so 根本不存在，FFI 每次都静默回退到纯 Dart。
    externalNativeBuild {
        cmake {
            path = file("../../native/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(requireNotNull(releaseStoreFile))
                storePassword = requireNotNull(releaseStorePassword)
                keyAlias = requireNotNull(releaseKeyAlias)
                keyPassword = requireNotNull(releaseKeyPassword)
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseSigning) signingConfigs.getByName("release") else null

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

dependencies {
    implementation(project(":flutter_webrtc"))
    // Keep the processor ABI aligned with flutter_webrtc 1.6.0.
    implementation("io.github.webrtc-sdk:android:144.7559.09")
    // Opus 编解码。纯 JVM 实现，不需要额外的 .so。
    // 版本与已发布的 Kotlin 版 alpha.7 一致，保证两版音频互通。
    implementation("io.github.jaredmdobson:concentus:1.0.2")
    testImplementation("junit:junit:4.13.2")
}

val verifyReleaseSigning by tasks.registering {
    doLast {
        require(hasReleaseSigning) {
            "Release requires android/key.properties or DAWNMESH_* signing environment variables. Use --debug for testing."
        }
        require(file(requireNotNull(releaseStoreFile)).isFile) { "Keystore not found" }
    }
}
tasks.matching { it.name == "validateSigningRelease" || it.name == "packageRelease" || it.name == "bundleRelease" }.configureEach {
    dependsOn(verifyReleaseSigning)
}
