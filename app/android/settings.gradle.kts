import java.io.File

pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.0.1" apply false
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
}

// AGP 9 bo ho tro getDefaultProguardFile('proguard-android.txt') (chua
// -dontoptimize chong R8) — flutter_inappwebview_android 1.1.3 van dung no
// trong android/build.gradle cua no → loi luc cau hinh du an (upstream chua
// co ban fix: pichillilorenzo/flutter_inappwebview#2852/#2887).
// Settings chay TRUOC khi Gradle danh gia project nao → sua pub cache o day
// la an toan, idempotent (chi ghi khi thay doi that su).
run {
    val pubCache = System.getenv("PUB_CACHE")
        ?: File(System.getProperty("user.home"), ".pub-cache").absolutePath
    val hosted = File(pubCache, "hosted/pub.dev")
    hosted.listFiles { f -> f.isDirectory && f.name.startsWith("flutter_inappwebview_android-") }
        ?.forEach { pkg ->
            val g = File(pkg, "android/build.gradle")
            if (!g.isFile) return@forEach
            val src = g.readText()
            val fixed = src.replace("'proguard-android.txt'", "'proguard-android-optimize.txt'")
            if (fixed != src) {
                g.writeText(fixed)
                println("patched AGP9-safe proguard file: ${g.absolutePath}")
            }
        }
}

include(":app")
