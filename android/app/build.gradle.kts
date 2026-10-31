import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ---------------------------------------------------------------------------
// release 签名配置：从 android/key.properties 读取，缺省时回退调试签名保证可构建
// ---------------------------------------------------------------------------
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

android {
    namespace = "com.echoloop.player"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.echoloop.player"
        // Android 8.0 / API 26 起步
        minSdk = 26
        targetSdk = 34
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // 只保留 arm64-v8a。注意：Flutter 的 Gradle 插件会按 -Ptarget-platform
        // 覆盖这里的 abiFilters，所以真正起作用的是构建命令里的
        //   flutter build apk --release --target-platform android-arm64
        // 下面这条是意图声明，配上 packaging 的 excludes 一起兜底。
        ndk {
            abiFilters += listOf("arm64-v8a")
        }
    }

    packaging {
        jniLibs {
            // 个别依赖（如 jni 包）会带上多份 libdartjni.so，
            // 这里统一剔除非 arm64 的，保证产出的包严格只有一种架构。
            excludes += listOf(
                "lib/armeabi-v7a/**",
                "lib/x86/**",
                "lib/x86_64/**",
            )
        }
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                // 相对路径以 android/ 为基准（key.properties 里写 keystore/xxx.jks）
                storeFile = keystoreProperties.getProperty("storeFile")?.let { rootProject.file(it) }
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // libmpv 为预编译原生库，关闭代码压缩避免反射/类名混淆带来的播放异常
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
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
    // 权限申请 / ContextCompat / NotificationCompat
    implementation("androidx.core:core-ktx:1.13.1")
    // 通知栏媒体样式（MediaStyle）
    implementation("androidx.media:media:1.7.0")

    // Native playback libraries are provided by the media_kit_libs_android_video dependency.
}
