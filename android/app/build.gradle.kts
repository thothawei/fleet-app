plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "dev.linefleet.line_fleet_app"
    compileSdk = flutter.compileSdkVersion
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

        val localProperties = java.util.Properties()
        val localPropertiesFile = rootProject.file("local.properties")
        if (localPropertiesFile.exists()) {
            localPropertiesFile.inputStream().use { localProperties.load(it) }
        }
        val mapsApiKey = localProperties.getProperty("GOOGLE_MAPS_API_KEY")
            ?: "YOUR_ANDROID_MAPS_API_KEY"
        manifestPlaceholders["googleMapsApiKey"] = mapsApiKey
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
