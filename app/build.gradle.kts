plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.nirog.app"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.nirog.app"
        minSdk = 24
        targetSdk = 34
        versionCode = (project.findProperty("buildNo") ?: "1").toString().toInt()
        versionName = "1.0.0." + (project.findProperty("buildNo") ?: "1")
    }

    buildTypes {
        release {
            isMinifyEnabled = false
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
