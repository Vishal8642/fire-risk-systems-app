plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "africa.fyrebox.fyrebox_technician"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = System.getenv("FYREBOX_APP_ID") ?: "africa.fyrebox.technician.preview"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    val clientKey = System.getenv("FYREBOX_KEYSTORE_FILE")
    signingConfigs {
        if (clientKey != null) {
            create("client") {
                storeFile = file(clientKey)
                storePassword = requireNotNull(System.getenv("FYREBOX_STORE_PASSWORD"))
                keyAlias = requireNotNull(System.getenv("FYREBOX_KEY_ALIAS"))
                keyPassword = requireNotNull(System.getenv("FYREBOX_KEY_PASSWORD"))
            }
        }
    }
    buildTypes {
        release {
            // Test-signed preview. Set FYREBOX_* variables for a client-owned production key.
            signingConfig = signingConfigs.getByName(if (clientKey != null) "client" else "debug")
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
