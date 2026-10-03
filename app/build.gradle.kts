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

    signingConfigs {
        create("alpha") {
            // Rilis memakai secret CI bila ada; kalau tidak, keystore tetap di repo
            // supaya tanda tangan SAMA di tiap build (update APK lewat pm install -r
            // tidak gagal karena beda signature).
            val ksPath = System.getenv("ALPHA_KEYSTORE_PATH") ?: "${rootDir}/keystore/alpha-release.jks"
            storeFile = file(ksPath)
            storePassword = System.getenv("ALPHA_STORE_PASSWORD") ?: "alpha-control"
            keyAlias = System.getenv("ALPHA_KEY_ALIAS") ?: "alpha"
            keyPassword = System.getenv("ALPHA_KEY_PASSWORD") ?: "alpha-control"
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            isShrinkResources = false
            signingConfig = signingConfigs.getByName("alpha")
        }
        debug {
            signingConfig = signingConfigs.getByName("alpha")
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
