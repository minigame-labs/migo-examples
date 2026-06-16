plugins {
    alias(libs.plugins.android.application)
}

android {
    namespace = "com.minigame.androiddemo"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.minigame.androiddemo"
        // Raised 21 -> 26: the migo runtime AAR pins minSdk 26 (Skia/NDK
        // Oreo baseline). Manifest merge fails below this.
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "1.0"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
}

dependencies {
    implementation(files("../../migo/platforms/android/dist/migo-debug.aar"))
}
