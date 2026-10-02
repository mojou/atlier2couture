import java.util.Properties

// Clé de signature officielle (fichiers hors git : android/key.properties + android/upload-keystore.jks).
val proprietesCle = Properties().apply {
    val fichier = rootProject.file("key.properties")
    if (fichier.exists()) fichier.inputStream().use { load(it) }
}

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.atelier.atelier_couture"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.atelier.atelier_couture"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (proprietesCle.containsKey("storeFile")) {
            create("release") {
                keyAlias = proprietesCle.getProperty("keyAlias")
                keyPassword = proprietesCle.getProperty("keyPassword")
                storeFile = file(proprietesCle.getProperty("storeFile"))
                storePassword = proprietesCle.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // Clé officielle si présente, sinon clé de test (pour compiler sur un autre PC).
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
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
