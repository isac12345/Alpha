# Alpha Control

Companion app for **Alpha + Uperf + fas-rs Fusion** Magisk module (root, Unisoc + Mali GPU).

## Features

- **Bottom Navigation**: Home, Games, Tuning, Display, About
- **Profile Selector**: Battery / Balanced / Performance (segmented control)
- **Game List**: Per-game profile assignment with search
- **Render Backend**: Select + Apply with active status
- **Tuning Log**: Preview (5 lines) + Full log dialog
- **Device Info**: SoC, GPU, CPU policies, storage, thermal + Redetect
- **Display**: Custom background (gallery pick, center-crop, EXIF rotation), transparency slider, reset to default
- **Resolution**: 60-100% presets + Apply/Reset Native
- **Dexopt**: App dex optimization
- **Auto-start**: Boot receiver for floating + profile monitor
- **Floating Bubble**: Collapsed circle (44dp) → Expanded pill (3 segments), drag+snap, long-press hide
- **Persistent Notification**: Shows active profile, tap → show floating, actions: Battery/Balanced/Perf
- **Quick Settings Tile**: Cycle profiles
- **Dark theme only**, modern black/white with teal accent

## Build

### Local (requires internet for Gradle deps)
```bash
./gradlew assembleDebug
./gradlew assembleRelease
```

### GitHub Actions (recommended)
1. Push to GitHub
2. Create keystore:
   ```bash
   keytool -genkeypair -alias alpha -keyalg RSA -keysize 2048 -validity 10000 -keystore alpha-release.jks
   ```
3. Add secrets to GitHub repo:
   - `KEYSTORE_BASE64`: `base64 -w0 alpha-release.jks`
   - `KEYSTORE_PASSWORD`: keystore password
   - `KEY_ALIAS`: `alpha`
   - `KEY_PASSWORD`: key password
4. Tag release: `git tag v2.0 && git push origin v2.0`
5. Signed APK published to GitHub Releases

## Version Sync

**IMPORTANT**: `versionCode` in `app/build.gradle.kts` MUST match `ALPHA_COMPANION_VER` in `common/companion_install.sh` (Magisk module). Update both together.

```kotlin
// app/build.gradle.kts
versionCode = 2
versionName = "2.0"
```

```bash
# common/companion_install.sh
ALPHA_COMPANION_VER=2
```

## Module Path Detection

App searches for module in:
- `/data/adb/modules/alpha_uperf_fasrs_fusion`
- `/data/adb/ksu/modules/alpha_uperf_fasrs_fusion`
- `/data/adb/ap/modules/alpha_uperf_fasrs_fusion`

Cached path stored in SharedPreferences.

## Key Files/Paths (must match module)

| Path | Purpose |
|------|---------|
| `/data/adb/alpha/current_state` | Active profile (battery\|balanced\|performance) |
| `/data/adb/alpha/detected.conf` | Hardware detection cache |
| `/data/adb/alpha/alpha.log` | Tuning log |
| `/data/adb/alpha/monitor.pid` | Monitor PID |
| `/data/adb/alpha/game_profile_map.conf` | Package → profile mapping |
| `/data/adb/alpha/render_backend` | Active render backend |

## Rename: Alpha Bubble → Alpha

| Old | New |
|-----|-----|
| App label | "Alpha Control" (unchanged) |
| Package | `com.alphabubble` (unchanged) |
| Service label | "Alpha Floating" |
| QS Tile label | "Alpha Profile" |
| Notification channel | "Alpha Profile" / "Alpha Floating" |
| APK output | `Alpha-<version>-<type>.apk` |
| UI text | "Alpha" (no "Bubble") |

## Credits

- **Alpha v1**: io/vm/thermal/net/gpu/devfreq tuning
- **Uperf Game Turbo**: Matt Yang & yinwanxi (thread/cgroup + AsoulOpt)
- **fas-rs**: shadow3 & shadow3aaa (frame-aware scheduler)
- **Companion rebuild**: somwan

## License

Same as upstream modules.