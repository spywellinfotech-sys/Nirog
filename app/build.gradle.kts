plugins {
    id("com.android.application")
}

android {
    namespace = "com.nirog.app"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.nirog.app"
        minSdk = 24
        targetSdk = 34
        versionCode = (project.findProperty("buildNo") ?: "1").toString().toInteger()
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
