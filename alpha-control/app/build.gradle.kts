plugins { id("com.android.application"); id("org.jetbrains.kotlin.android") }
android { namespace = "com.alphabubble"; compileSdk = 34
  defaultConfig { applicationId = "com.alphabubble"; minSdk = 26; targetSdk = 34
    versionCode = System.getenv("GITHUB_RUN_NUMBER")?.toIntOrNull() ?: 1
    versionName = "v1"
  }
  buildFeatures { viewBinding = true }
  buildTypes { release { isMinifyEnabled = false; proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro") } }
  compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
  kotlinOptions { jvmTarget = "17" }
  signingConfigs { create("release") { storeFile = file(System.getenv("KEYSTORE_PATH") ?: "release.keystore")
    storePassword = System.getenv("KEYSTORE_PASSWORD") ?: ""
    keyAlias = System.getenv("KEY_ALIAS") ?: "alpha"
    keyPassword = System.getenv("KEY_PASSWORD") ?: (System.getenv("KEYSTORE_PASSWORD") ?: "")
  } }
  buildTypes { named("release") { signingConfig = signingConfigs.getByName("release") } }
}
dependencies {
  implementation("androidx.core:core-ktx:1.12.0")
  implementation("androidx.appcompat:appcompat:1.6.1")
  implementation("androidx.recyclerview:recyclerview:1.3.2")
  implementation("androidx.constraintlayout:constraintlayout:2.1.4")
  implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
  implementation("com.google.android.material:material:1.11.0")
}
