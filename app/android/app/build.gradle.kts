plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

/** A build value from `-P` or the environment. */
fun buildValue(name: String): String? =
    (project.findProperty(name) as String?)?.takeIf { it.isNotEmpty() }
        ?: System.getenv(name)?.takeIf { it.isNotEmpty() }

fun requiredValue(name: String): String =
    buildValue(name) ?: throw GradleException("$name is needed with DSIP_FCM_APP_ID")

android {
    namespace = "com.thevoiceguy.dsip"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications (the app's alerts) needs Java 8+'s time APIs on every Android it runs on
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // The desktop's id too (macOS bundle, Linux application id).
        applicationId = "com.thevoiceguy.dsip"
        // Android 8.0: the system's call screen for an app's own calls (a self-managed ConnectionService, A5b).
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Waking the app while it sleeps (A5d-2; the Wake Profile): the publisher's push gateway (its DID) and the
        // Firebase project it pushes through, as the values google-services.json would give. From the environment or
        // `-P` at build time, so no project is kept in the repository; without them the app builds with push off.
        resValue("string", "dsip_push_gateway", buildValue("DSIP_PUSH_GATEWAY") ?: "")
        val fcmAppId = buildValue("DSIP_FCM_APP_ID")
        if (fcmAppId != null) {
            resValue("string", "google_app_id", fcmAppId)
            resValue("string", "gcm_defaultSenderId", requiredValue("DSIP_FCM_SENDER_ID"))
            resValue("string", "google_api_key", requiredValue("DSIP_FCM_API_KEY"))
            resValue("string", "project_id", requiredValue("DSIP_FCM_PROJECT_ID"))
        }
    }

    buildFeatures {
        resValues = true
    }

    // One key for every release build, so a new APK installs over the old one and the app's data (identity,
    // settings, contacts, history) stays: Android refuses an update signed with another key, and the debug key is
    // made afresh on each CI runner. The keystore (PKCS12) and its password come from the environment or `-P`
    // (CI: repository secrets); without them, the debug key, for local builds.
    val keystore = buildValue("DSIP_ANDROID_KEYSTORE")
    signingConfigs {
        if (keystore != null) {
            create("dsip") {
                storeFile = file(keystore)
                storeType = "pkcs12"
                storePassword = buildValue("DSIP_ANDROID_KEYSTORE_PASSWORD")
                    ?: throw GradleException("DSIP_ANDROID_KEYSTORE_PASSWORD is needed with DSIP_ANDROID_KEYSTORE")
                keyAlias = buildValue("DSIP_ANDROID_KEY_ALIAS") ?: "dsip"
                keyPassword = storePassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(if (keystore != null) "dsip" else "debug")
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
    // NotificationCompat.CallStyle and ServiceCompat for the call's notification and service (CallService.kt).
    implementation("androidx.core:core:1.13.1")
    // The pushes that wake the app (Push.kt).
    implementation(platform("com.google.firebase:firebase-bom:34.19.0"))
    implementation("com.google.firebase:firebase-messaging")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
