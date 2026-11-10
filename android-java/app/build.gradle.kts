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
    implementation(files("../libs/migo.aar"))
    // A file AAR brings none of the libraries migo uses: Kotlin's standard library (its TLS
    // verifier) and ZXing (scanCode's decoder), at the versions its release lists.
    implementation(libs.kotlin.stdlib)
    implementation(libs.zxing.core)
}
