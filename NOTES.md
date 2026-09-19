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

## Bug 5 — SELESAI: Kotlin compilation errors (100+ → 0)
- Sumber: `gh run view 35424715970 --log-failed` → `:app:compileDebugKotlin FAILED`.
- Batch 1 (commit 9e6fd10, run 35425048357: 100+ → 64 error):
  - `RootShell.kt:18` const val List → val; `:62-64` map SuExecutor.ExecResult → RootShell.ExecResult; bare `return` dalam `withContext` → `return@withContext` (11 lokasi); `m.groupValues()[n]` → `m.groupValues[n]`.
  - `LogFormat.kt` groupValues() → groupValues[] (6 lokasi).
  - `FloatingBubbleService.kt:60-62` const val → val; tambah `import kotlin.math.abs` + `androidx.core.animation.doOnEnd`; 13 hex Long → `.toInt()`; `dotRadius` Int → Float.
- Batch 2 (commit 12f7122, run 35425305786: 64 → 40 error; RootShell + FloatingBubble bersih):
  - `RootShell.kt:122` `var w=0, h=0, dens=0` → 3 baris `var` (Kotlin tak boleh deklarasi koma).
  - `FloatingBubbleService` `Gravity.TOP | Gravity.START` → `or` (3 lokasi, Kotlin tak punya `|`); animator `?.animate().` → `?.animate()?.`; `(collapsedView as? FrameLayout)`, `(expandedView as? ViewGroup)`, `(container as? ViewGroup)` casts; hapus `getLocationOnScreen(arrayOf)` ganda.
- Batch 3 (commit 1d2a4b6, run 35425609761: 40 → 3 error):
  - `AlphaApp.kt`: hapus libsu `com.topjohnwu.superuser.Shell` (dependensi tak ada) → Application kosong.
  - `AddGameDialog/DexoptDialog/GamesFragment`: tambah `import androidx.core.widget.addTextChangedListener`; `DexoptDialog.filterApps` `pm` → `requireContext().packageManager`; `OnGameAddedListener` → `fun interface`; `GameAdapter(...)` wiring named args + object listener.
  - `FloatingBubbleService`: `getToggleIntent/getShowIntent` instance → companion `@JvmStatic`; `ProfileMonitorService`: hapus import salah `com.alphabubble.FloatingBubbleService`, tambah `android.graphics.drawable.Icon` → `IconCompat`; `DisplayFragment` + `TuningFragment` tambah imports (DexoptDialog, ProfileMonitorService, FloatingBubbleService, LogAllDialog, RecyclerView, DiffUtil).
- Batch 4 (commit a70ddc2, run 35425798781: 3 → 0 error Kotlin):
  - `AddGameDialog.AppAdapter` inner class → biasa + param `getAll: () -> List<AppRow>` (inner tak boleh nested class di posisi itu).
  - `ProfileMonitorService` `Icon.createWithResource` → `IconCompat.createWithResource` (compat Builder butuh IconCompat).
- Percobaan: 4 batch, tiap batch menurunkan error. Tidak ada error yang gagal 3x.

## Bug 6 — SELESAI: Orphaned framework res (DateTimeView)
- Gejala: run 35425798781 Kotlin 0 error, tapi `:app:compileDebugJavaWithJavac FAILED` → `cannot find symbol: class DateTimeView` di `NotificationTemplatePartTimeBinding.java` (9 errors).
- Akar masalah: `app/src/main/res/layout/notification_{action,action_tombstone,template_custom_big,template_icon_group,template_part_chronometer,template_part_time}.xml` adalah copy framework (ada `<DateTimeView>`, hidden API) + `values/public.xml` artifact apktool. Tidak direferensikan kode manapun (`grep R.layout.notification` kosong).
- Solusi (commit 0cc0936): `git rm` 6 layout + `public.xml`.
- Verifikasi: run 35425996649 → ✓ Build Debug APK, ✓ Upload APK dalam 2m36s.

## Hasil build terakhir (apa adanya)
```
Run 35425996649 (push 0cc0936): SUCCESS
- Set up job ✓, checkout ✓, JDK 17 ✓, chmod gradlew ✓, Build Debug APK ✓, Upload APK ✓
- Link: https://github.com/isac12345/Alpha/actions/runs/35425996649
- Artefak: Alpha-Debug-APK (5.4MB di Actions) → diunduh ke build-output/app-debug.apk (6.2M)
- Stash Termux (tidak di-push): stash@{0} termux-workaround-mirror-timeout (settings.gradle.kts + gradle.properties)
```
