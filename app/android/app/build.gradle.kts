import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "cc.seeed.voice"
    // flutter_web_auth_2 -> androidx.browser:browser:1.9.0 requires compileSdk 36+
    compileSdk = 36
    // Must match a *fully installed* NDK under ANDROID_SDK/ndk/<revision> (with source.properties).
    // 28.2.13676358 was left incomplete (.installer only) — use a complete side-by-side install.
    ndkVersion = "28.0.12674087"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "cc.seeed.voice"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // `record` / `ffmpeg_kit_flutter_new` 插件在 Android 端需要更高的 minSdk。
        // Flutter 默认 flutter.minSdkVersion 通常为 21，这里提升以避免 manifest merger 失败。
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    /**
     * Release 签名（安全做法）
     *
     * - 本地：在 `android/key.properties` 放置 keystore 路径与密码（不提交到 git）
     * - CI：用环境变量注入（同样不落盘）
     *
     * key.properties 示例见：android/key.properties.example
     */
    val keystoreProperties = Properties()
    val keystorePropertiesFile = rootProject.file("key.properties")
    if (keystorePropertiesFile.exists()) {
        keystoreProperties.load(FileInputStream(keystorePropertiesFile))
    }

    val storeFilePath = (keystoreProperties["storeFile"] as String?)
        ?: System.getenv("ANDROID_KEYSTORE_FILE")
    val storePasswordValue = (keystoreProperties["storePassword"] as String?)
        ?: System.getenv("ANDROID_KEYSTORE_PASSWORD")
    val keyAliasValue = (keystoreProperties["keyAlias"] as String?)
        ?: System.getenv("ANDROID_KEY_ALIAS")
    val keyPasswordValue = (keystoreProperties["keyPassword"] as String?)
        ?: System.getenv("ANDROID_KEY_PASSWORD")

    val canSignRelease = !storeFilePath.isNullOrBlank() &&
        !storePasswordValue.isNullOrBlank() &&
        !keyAliasValue.isNullOrBlank() &&
        !keyPasswordValue.isNullOrBlank()

    // 只在真正需要 release 构建时才强制要求签名，避免影响 debug（flutter run/assembleDebug）
    val isReleaseTaskRequested = gradle.startParameter.taskNames.any { it.contains("release", ignoreCase = true) }
    if (isReleaseTaskRequested && !canSignRelease) {
        throw GradleException(
            "Missing Android release signing config. " +
                "Create android/key.properties or set env vars: " +
                "ANDROID_KEYSTORE_FILE, ANDROID_KEYSTORE_PASSWORD, ANDROID_KEY_ALIAS, ANDROID_KEY_PASSWORD."
        )
    }

    signingConfigs {
        if (canSignRelease) {
            create("release") {
                storeFile = file(storeFilePath!!)
                storePassword = storePasswordValue
                keyAlias = keyAliasValue
                keyPassword = keyPasswordValue
            }
        }
    }

    buildTypes {
        debug {
            // 方案 B：Debug 与 Release 共用 `release` 签名（需 android/key.properties 或 CI 环境变量）。
            // 这样 `flutter run` 安装的 APK 与上架包 SHA-1 一致，Google OAuth Android 客户端只需填一个指纹。
            // 未配置正式密钥时仍使用默认 android.debug.keystore。
            if (canSignRelease) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
        release {
            // Release 使用正式签名（安全：密钥不入库）
            signingConfig = if (canSignRelease) signingConfigs.getByName("release") else signingConfigs.getByName("debug")
            // 关闭代码压缩/混淆，避免 Pigeon 通道被裁剪导致 channel-error
            // （shared_preferences、google_sign_in 等插件的原生通道无法建立连接）
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

flutter {
    source = "../.."
}
