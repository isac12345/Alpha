plugins { id("com.android.application"); id("org.jetbrains.kotlin.android") }
android { namespace = "com.alphabubble"; compileSdk = 34
  defaultConfig { applicationId = "com.alphabubble"; minSdk = 26; targetSdk = 34; versionCode = 1; versionName = "v1" }
  buildTypes { release { isMinifyEnabled = false } }
  compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
  kotlinOptions { jvmTarget = "17" }
}
dependencies { }
