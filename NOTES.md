# NOTES.md — Alpha Build Debug (Termux, 2026-09-19)

Repo: `isac12345/Alpha` (private) + lokal `~/AlphaRebuild` (branch master, up-to-date dengan origin/master).
Perintah resmi dari README + workflow: `./gradlew assembleDebug` (JDK 17, Gradle 8.5, AGP 8.3.2).
Koneksi GitHub: `gh auth status` → Logged in sebagai `isac12345`, token valid, `gh repo list` → Alpha (private), Hsin (public).

## Bug 1 — SELESAI: Missing Gradle Wrapper (gradlew + jar)
- Gejala: `ls gradlew*` → No such file. `git ls-files` tidak ada gradlew/jar. `.github/workflows/build.yml` jalankan `chmod +x gradlew && ./gradlew assembleDebug` → pasti gagal di CI dengan `gradlew: No such file`.
- Akar masalah: repo hanya commit `gradle/wrapper/gradle-wrapper.properties`, tidak commit script wrapper.
- Solusi: generate wrapper dengan Gradle 8.5 + JDK 17: `/tmp/opencode/gradle-8.5/bin/gradle wrapper --gradle-version 8.5`. Menghasilkan `gradlew`, `gradlew.bat`, `gradle/wrapper/gradle-wrapper.jar`, update `gradle-wrapper.properties`.
- Verifikasi: `./gradlew --version` → Gradle 8.5, `./gradlew assembleDebug` jalan (gagal lanjut di SDK error, bukan wrapper error).
- Status file: `gradlew`, `gradlew.bat`, `gradle-wrapper.jar`, `gradle-wrapper.properties` → WAJIB di-commit ke GitHub untuk betulkan CI.

## Bug 2 — WORKAROUND LOKAL: Plugin 403 (repo.maven.apache.org + plugins.gradle.org)
- Gejala: `gradle assembleDebug` (system Gradle 9.7.1) → `Plugin org.jetbrains.kotlin.android:1.9.20 was not found`, `Failed to get resource: GET HTTP 403` untuk mavenCentral + gradlePluginPortal.
- Investigasi:
  - `curl` + `python urllib` + `Java HttpURLConnection` ke URL yang sama → 200. Hanya Apache HttpClient Gradle → 403.
  - Coba `--refresh-dependencies` + daemon restart → tetap 403 (percobaan 1 gagal).
  - Tambah `maven("https://repo1.maven.org/maven2")` → tetap 403 untuk repo1 via Gradle (percobaan 2 gagal, bukti client-specific bukan host-specific).
  - Tambah `maven("https://maven-central.storage-download.googleapis.com/maven2")` → Downloading sukses, `Resolved plugin` (percobaan 3 sukses).
- Akar masalah: filter jaringan Termux memblokir Gradle Apache HttpClient ke Cloudflare-fronted hosts, tapi meloloskan ke `*.storage-download.googleapis.com`.
- Solusi lokal (tidak untuk CI): taruh Google mirror paling atas di `pluginManagement` + `dependencyResolutionManagement` di `settings.gradle.kts`.
- Catatan: CI ubuntu-latest kemungkinan tidak kena blokir ini, jadi mirror tidak wajib di-push.

## Bug 3 — SELESAI (identifikasi): Gradle 9.7.1 vs 8.5 + JDK 21 vs 17
- Gejala: dengan system Gradle 9.7.1 → `org/gradle/api/internal/HasConvention` + `Failed to query buildFlowServiceProperty`.
- Akar masalah: Kotlin 1.9.20 + AGP 8.3.2 tidak support Gradle 9. Project minta Gradle 8.5 (wrapper properties) + JDK 17 (workflow setup-java).
- Solusi: download `gradle-8.5-bin.zip` ke `/tmp/opencode`, pakai `JAVA_HOME=/usr/lib/jvm/java-17-openjdk` (sudah terinstall). Verifikasi: error HasConvention hilang.
- File uncommitted: binary di `/tmp` saja, tidak ubah repo.

## Bug 4 — BELUM DIPERBAIKI (blocker lokal): No Android SDK + dl.google.com timeout
- Gejala awal: `Could not HEAD https://dl.google.com/... Read timed out` untuk AGP 8.3.2 JARs. `curl` 11MB dalam 5 detik → network oke, timeout Gradle 30s kekecilan.
- Solusi parsial: tambah di `gradle.properties` → `systemProp.http.connectionTimeout=120000`, `socketTimeout=120000`, `org.gradle.internal.http.*=120000`, `org.gradle.network.retry.maxAttempts=5`. Reorder repo mirror-first. Hasil: deps ke-download, lanjut ke error berikutnya.
- Gejala akhir (tersisa): `SDK location not found. Define ANDROID_HOME or sdk.dir in local.properties` di `:app:compileDebugJavaWithJavac`.
- Investigasi SDK:
  - `echo $ANDROID_HOME` kosong, `sdkmanager` tidak ada, `~/Android`, `/opt/android` tidak ada.
  - `/tmp/opencode/sdk` hanya berisi `android.jar` 137MB, bukan full SDK.
  - Termux ada `aapt`, `adb`, `apksigner`, `d8` tapi tidak ada full SDK. Official cmdline-tools butuh glibc, Termux pakai bionic → instalasi full SDK tidak trivial.
- Keputusan: STOP setelah 2 percobaan untuk error ini (reorder + timeout). Tidak coba install full SDK (berat, >1GB, risiko gagal di Termux). Rekomendasi resmi README: pakai GitHub Actions.
- Status file: `gradle.properties` timeout + `settings.gradle.kts` mirror adalah workaround lokal Termux, belum tentu perlu di-push.

## Hasil build terakhir (apa adanya)
```
./gradlew assembleDebug (Gradle 8.5, JDK 17) di GitHub Actions run 35424715970:
- Wrapper: FIXED (Grant execute permission passed)
- Build Debug APK: FAILED di :app:compileDebugKotlin, 100+ error Kotlin (lihat log run)
- Contoh: RootShell.kt const val List, type mismatch SuExecutor vs RootShell, return tanpa label, groupValues() dipanggil sebagai fungsi; FloatingBubbleService const val, warna Long vs Int, import abs/doOnEnd hilang; Fragments unresolved references
- Link: https://github.com/isac12345/Alpha/actions/runs/35424715970
```

## Bug 5 — IN PROGRESS (batch 1): Kotlin compilation errors
- Sumber: `gh run view 35424715970 --log-failed` → `:app:compileDebugKotlin FAILED`.
- Fix batch 1 (belum di-push saat catatan ini ditulis):
  - `RootShell.kt:18` const val List → val; `:62-64` map SuExecutor.ExecResult → RootShell.ExecResult; bare `return` dalam `withContext` → `return@withContext` (11 lokasi); `m.groupValues()[n]` → `m.groupValues[n]` (groupValues adalah List property).
  - `LogFormat.kt` groupValues() → groupValues[] (6 lokasi).
  - `FloatingBubbleService.kt:60-62` const val → val; tambah `import kotlin.math.abs` + `androidx.core.animation.doOnEnd`; 13 literal warna hex Long → `.toInt()`; `dotRadius` Int → Float (drawCircle butuh Float).
- Belum disentuh (tunggu log fresh): smart cast mutable, nullable ViewPropertyAnimator ?., getChildAt, syntax 196/220/493/630, Fragments + ProfileMonitorService unresolved, GameAdapter listener mismatch.
- Percobaan: 1 (batch 1).

## Next step disarankan
1. Commit + push hanya file wrapper: `gradlew`, `gradlew.bat`, `gradle/wrapper/gradle-wrapper.jar`, `gradle/wrapper/gradle-wrapper.properties`.
2. Trigger `gh workflow run` / `git tag` untuk build APK di GitHub Actions (ubuntu + JDK17 + SDK otomatis).
3. Kalau mau build lokal di Termux, perlu install full SDK (tidak disarankan) atau pakai mirror + timeout yang ada di working tree saat ini.
4. `versionCode=2` sinkron dengan `ALPHA_COMPANION_VER=2` → OK, jangan lupa bump berbarengan saat rilis.
