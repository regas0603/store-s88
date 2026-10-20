plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Danh tính app (bundle id, tên hiển thị, ký) — tools/dynpub.sh / tools/cmd/run.sh
// truyền qua env theo apps/<bundleId>/app.yaml. KHÔNG có bundle id mặc định:
// thiếu env → dừng, tránh build nhầm sang app khác.
val appBundleId: String = System.getenv("APP_BUNDLE_ID")?.takeIf { it.isNotEmpty() }
    ?: throw GradleException(
        "Thiếu APP_BUNDLE_ID — build qua `bash tools/dynpub.sh` hoặc chạy dev qua " +
            "`bash tools/cmd/run.sh` (chọn app trong apps/<bundleId>/)",
    )
val appDisplayName: String = System.getenv("APP_DISPLAY_NAME")?.takeIf { it.isNotEmpty() } ?: "App"
val appKeystore: String? = System.getenv("APP_KEYSTORE")?.takeIf { it.isNotEmpty() }

android {
    namespace = "com.example.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = appBundleId
        manifestPlaceholders["appLabel"] = appDisplayName
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (appKeystore != null) {
            create("app") {
                storeFile = file(appKeystore)
                storePassword = System.getenv("APP_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("APP_KEY_ALIAS")
                keyPassword = System.getenv("APP_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            // Có keystore của app (app.yaml) → ký bằng nó; không thì ký debug
            // để `flutter run --release` vẫn chạy được.
            signingConfig = if (appKeystore != null) signingConfigs.getByName("app")
                else signingConfigs.getByName("debug")
        }
    }
}

// Release: chỉ arm64. Engine ddm chỉ build android_release_arm64 → không có
// libflutter/libapp cho x86_64 / armeabi-v7a; .so plugin (rive_native, sentry…)
// của các ABI đó chỉ là ~33MB thừa. Không dùng ndk.abiFilters ở buildType: Flutter
// Gradle plugin ghi đủ 3 ABI vào defaultConfig và AGP gộp (union) 2 bên.
// Debug giữ mọi ABI cho emulator.
androidComponents {
    onVariants(selector().withBuildType("release")) { variant ->
        variant.packaging.jniLibs.excludes.addAll(
            listOf("lib/armeabi-v7a/**", "lib/x86_64/**", "lib/x86/**"),
        )
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
