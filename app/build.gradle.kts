import java.io.File

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

// versionCode = isi version.txt di root repo (sumber tunggal, sama dengan
// ALPHA_COMPANION_VER di module/common/companion_install.sh).
val alphaVersionCode: Int = File(rootDir, "version.txt").readText().trim().toInt()

android {
    namespace = "com.alphabubble"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.alphabubble"
        minSdk = 26
        targetSdk = 34
        versionCode = alphaVersionCode
        versionName = "2.0-fusion-$alphaVersionCode"
    }

    // Keystore dan password TIDAK ada di repo. CI mengisinya dari GitHub Secrets
    // (lihat .github/workflows/build.yml). Tanpa env ini, build memakai debug key
    // (hanya untuk uji lokal; APK-nya tidak bisa menimpa APK rilis).
    val ksPath: String? = System.getenv("ALPHA_KEYSTORE_PATH")
    signingConfigs {
        if (ksPath != null) {
            create("alpha") {
                storeFile = file(ksPath)
                storePassword = System.getenv("ALPHA_STORE_PASSWORD")
                keyAlias = System.getenv("ALPHA_KEY_ALIAS")
                keyPassword = System.getenv("ALPHA_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfig = signingConfigs.findByName("alpha") ?: signingConfigs.getByName("debug")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
    buildFeatures {
        compose = true
    }
    composeOptions {
        kotlinCompilerExtensionVersion = "1.5.14"
    }
    lint {
        abortOnError = false
        checkReleaseBuilds = false
    }
    packaging {
        resources.excludes += "/META-INF/{AL2.0,LGPL2.1}"
    }
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2024.06.00")
    implementation(composeBom)
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.activity:activity-compose:1.9.0")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.2")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.2")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.2")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material3:material3")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
}
