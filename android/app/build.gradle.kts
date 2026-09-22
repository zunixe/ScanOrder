import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.scanorder.scanorder"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "com.scanorder.scanorder"
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Flavor distribusi: play (Google Play, app user) vs admin (build internal).
    // Keduanya memakai keystore & konfigurasi signing yang SAMA.
    //
    // Flavor `play`: SATU-SATUNYA yang boleh diupload ke Google Play.
    //   flutter build appbundle --release --flavor play --dart-define-from-file=.env
    //
    // Flavor `admin`: build internal (JANGAN pernah diupload store).
    //   flutter build apk --release --flavor admin -t lib/main_admin.dart \
    //     --dart-define-from-file=.env
    // Entry Dart: -t lib/main_admin.dart. AppId beda supaya bisa
    // ter-install berdampingan dengan app user di satu HP.
    flavorDimensions += "store"
    productFlavors {
        create("play") {
            dimension = "store"
            applicationId = "com.scanorder.scanorder"
            manifestPlaceholders["appName"] = "ScanOrder"
        }
        create("admin") {
            dimension = "store"
            applicationId = "com.scanorder.scanorder.admin"
            versionNameSuffix = "-admin"
            // Nama beda supaya gampang dibedakan di home screen.
            manifestPlaceholders["appName"] = "ScanOrder Admin"
        }
    }

    // Generate separate APKs per ABI instead of a single fat APK (release only)
    // Debug builds use Flutter's ndk.abiFilters which conflicts with splits
    splits {
        abi {
            isEnable = project.hasProperty("split-apk")
            reset()
            include("armeabi-v7a", "arm64-v8a", "x86_64")
            isUniversalApk = false
        }
    }

    // versionCode = buildNumber langsung (naik +1 per rilis, MULAI rilis
    // 1.0.5+23 → versionCode 23... dst). Rilis lama memakai formula lama
    // buildNumber*10 (…210, 220, 230) sehingga masih di atas angka-angka ini.
    // Setelah 230, urutan: 231, 232, 233, …
    androidComponents {
        onVariants { variant ->
            variant.outputs.forEach { output ->
                output.versionCode.set(flutter.versionCode.toInt())
            }
        }
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
