plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "dev.linefleet.line_fleet_app"
    // 明確設 36：geolocator 等相依套件要求 compileSdk >= 36，
    // flutter.compileSdkVersion 目前解析為 33 會讓 AAR metadata 檢查失敗。
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    flavorDimensions += "role"
    productFlavors {
        create("driver") {
            dimension = "role"
            applicationIdSuffix = ".driver"
        }
        create("customer") {
            dimension = "role"
            applicationIdSuffix = ".customer"
        }
    }

    defaultConfig {
        applicationId = "dev.linefleet.line_fleet_app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
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

// 有 google-services.json 時才套用（見 README / android/app/google-services.json.example）
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}
