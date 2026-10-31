# Alpha Fusion v3 + Alpha Control

Alpha Fusion is a root module that tunes the kernel/CPU/GPU and a companion Android app
(Alpha Control) that controls it. The module does the work; the app only sends commands
through `su` and shows status.

Everything runs locally. No account, no telemetry.

## Requirements

- Root: Magisk, KernelSU, or APatch (APatch needs a recent version; older builds may lack
  the overlayfs support the installer uses).
- ARM64 device.
- Android 12 or newer for all features. On older Android, fas-rs and Game Mode do not run.

## Features

- Profiles: **Daily**, **Balanced**, **Performance**.
- **Overdrive**: full CPU/GPU floors for short heavy sessions, with a thermal guard and
  automatic restore when the game closes.
- **Game Mode** per game: mode (standard/performance/battery/custom), render scale, and
  optional FPS cap. Applied when the game opens and restored when it closes.
- **Floating HUD**: FPS, CPU, GPU, and temperature on top of the game.
- **Screen recording** (built-in `screenrecord`) and **FPS data recording** to CSV.
- **Performance & FPS**: history of recorded sessions and a comparison view.
- **Memory**: PSI and MGLRU status/tuning.
- **Check features**: one-pass self test of the running setup.

## Install

1. Flash `Alpha-Fusion-v53.zip` in Magisk/KernelSU/APatch.
2. Reboot.
3. Install `AlphaControl-v53.apk` (also bundled inside the zip under `companion/`).
4. Open the app and grant root when asked.

Update = flash the newer zip and reboot; then install the newer APK.

## Check it works

Open **Alat > Cek fitur** (Tools > Check features) in the app. It prints one line per check
(`OK`, `GAGAL`, `LEWAT`). Some checks are `LEWAT` until a game is running or Overdrive is on.

## Known limitations (tested, not guesses)

- Tested only on **itel P65 (Unisoc T606, Android 14)**. Other phones and chipsets are
  untested; some sysfs nodes and vendor thermal presets differ per device.
- Game FPS depends on the game exposing a readable `SurfaceView` layer through
  SurfaceFlinger. Games that do not (or ROMs with a broken `timestats`) show no FPS.
- GPU usage stays empty when the kernel has no GPU load/busy node. Frequencies still show.
- Vendor thermal presets are currently skipped on Unisoc (`[THERMAL] [SKIPPED] vendor unisoc`).
- On some ROMs `cmd game list-configs` keeps an intervention after the game closes even
  though the module runs `cmd game reset`. Reset manually with
  `su -c 'cmd game reset <package>'` if needed.

## Repo layout

- `module/` - root module (shell). All tuning logic lives here.
- `app/` - Alpha Control (Kotlin/Jetpack Compose).
- `tools/check_module.sh` - version consistency check.
- Builds run on GitHub Actions; artifacts are `AlphaControl-v53.apk` and
  `Alpha-Fusion-v53.zip`.

## License

See `LICENSE` and `NOTICE-gamebank.md`.
