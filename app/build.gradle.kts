plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.yadaplus.app"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.yadaplus.app"
        minSdk = 24
        targetSdk = 36
        versionCode = (project.findProperty("buildNo") ?: "1").toString().toInt()
        versionName = "1.0.0." + (project.findProperty("buildNo") ?: "1")
    }

    // Release signing comes from environment variables set by the "Build Play Store bundle" workflow. Local and debug builds ignore it.
    val ksPath = System.getenv("KEYSTORE_PATH")
    signingConfigs {
        // Fixed test key (public on purpose, never used for the Play Store) so every CI build can update the one before it.
        getByName("debug") {
            storeFile = file("keystore/debug.keystore")
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }
        if (ksPath != null) {
            create("release") {
                storeFile = file(ksPath)
                storePassword = System.getenv("KEYSTORE_PASSWORD")
                keyAlias = System.getenv("KEY_ALIAS")
                keyPassword = System.getenv("KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            if (ksPath != null) signingConfig = signingConfigs.getByName("release")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {
    // Firebase Cloud Messaging: notifications in the phone tray, even when the app is closed.
    implementation(platform("com.google.firebase:firebase-bom:33.5.1"))
    implementation("com.google.firebase:firebase-messaging")
    implementation("androidx.core:core:1.13.1")
}
