plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.android)
}

android {
    namespace = "com.example.migo.sample"
    compileSdk = 35

    defaultConfig {
        minSdk = 26
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = "11"
    }

    buildFeatures {
        buildConfig = true
    }
}

dependencies {
    // compileOnly: this module only needs migo's API surface to typecheck the
    // snippets, and AGP refuses to bundle a local .aar into another AAR's
    // packaging step (bundleDebugAar fails with "Direct local .aar file
    // dependencies are not supported when building an AAR"). Nothing consumes
    // :snippets at runtime, so the compile-time classpath is all that matters.
    compileOnly(files("../libs/migo.aar"))
}
