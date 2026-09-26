# STATE.md — Alpha Fusion v2 (branch fusion-v2)

- ZIP-V34 (2026-09-25, leader): kedua fix L1 di-merge ke fusion-v2
  (9bde84a monitor, 0fbfd5f GPU opsi A) + bump modul-only 33->34
  (f58fe01, APK tetap 20). Build zip lokal Termux:
  /sdcard/alpha/Alpha-Fusion-v34.zip (5594350 byte, md5
  e41a4a26b9e30f27f5f42e912965b3c6), 182 entries, tanpa wrapper,
  META-INF di root, versionCode=34, tanpa .jks/rahasia, md5
  engine.sh+monitor.sh+APK identik repo, SEMUA skrip sh -n OK dari
  hasil ekstrak. Zip lama Alpha-Fusion-v1.zip (v33) dibiarkan.
  TUNGGU: flash + tes HP (L2). BELUM push ke GitHub/arsip.
  JEBRAKAN ZIP (penting, jangan diulang): rebuild zip pakai
  python zipfile TANPA set create_system=3 + create_version=30 ->
  Info-ZIP unzip tidak restore permission, hasil ekstrak mode 000
  (file tidak bisa dibaca/dijalankan). Yang benar: `git archive |
  tar -x` ke staging, chmod dipaks (755 skrip+biner, 644 lainnya),
  lalu `zip -r -9 -X`. Verifikasi wajib: ekstrak ulang + ls -l +
  sh -n (bukan cuma testzip).

- GPU-PERF-FLAPPING / OPSI-A (2026-09-25, leader + dev-modul
  work/gpu-perf-tune): complaint user = FPS "kesendat mendadak" di profil
  performance. Analisis (leader, live): satuan gpu_pollingtime TIDAK bisa
  diverifikasi publik — param vendor Unisoc, tidak ada di upstream mali_kbase
  (upstream punya DEFAULT_PM_DVFS_PERIOD 100ms, bukan gpu_pollingtime) →
  jangan turunkan angkanya. Bukti live: devfreq node 23100000.gpu =
  governor simple_ondemand, polling_interval 50 (ms), TIDAK ada node
  up_threshold/down_threshold (default kernel 90/5), min_freq 384MHz TIDAK
  pernah dikunci modul (hanya max_freq), trans_stat = 12.772x flapping
  850<->384MHz. Tune polling_interval di repo hanya jalan Adreno
  (tune_gpu_adreno_kgsl), jalur Mali tidak pernah menyentuhnya. Catatan
  jujur: saat benchmark 19:48-20:21 gameboost extreme sudah memaksa
  governor=performance, jadi drop saat itu BUKAN terutama karena downclock
  GPU; kandidat ini memperbaiki jendela performance non-gameboost.
  Opsi A (dipilih user): (1) kbase performance upthreshold 15->45
  (pollingtime tetap 1 = batas bawah), (2) Mali performance menulis
  polling_interval 10ms (GPU_PERF_POLLING_MS, default ALPHA_GPU_POLLING_MS)
  dengan gate thermal + guard writable; profil lain TIDAK ditulis.
  L1: sh -n 0, diff 16+/1- 1 file, shellcheck identik baseline (SC3043:118
  SC2034:2), harness sysfs palsu 3 skenario PASS (performance poll=10
  kbase 1/1/45; battery poll tetap 50 kbase 0/8/88; thermal gate poll
  tetap 50 + log SKIPPED). Commit 572c7e8, belum merge/push.
  TUNGGU: user apply + tes HP (L2). Kalau ramp jadi makin lambat, revert
  angka upthreshold ke 15 (kbase) — polling_interval 10ms tetap.
  PELAJARAN: harness wajib set GPU_ADRENO_SKIP=0 (profiles.sh yang mengaturnya
  per profil); tanpa itu tune_gpu_mali return dini dan semua tes false-pass.

- MONITOR-EVENT-POLL (2026-09-25, leader + dev-modul work/monitor-event-poll):
  Fix 3 bug event/polling di common/monitor.sh (48+/12-, hanya file itu).
  Temuan kunci: "deaf (446s on, 0 parsed)" adalah FALSE POSITIVE — log HP
  membuktikan tag event ADA di ROM ini ("healthy (10 parsed in 46s)" +
  4x APPLY-EVENT); EVENT_ON_SECS tak pernah direset sementara count file
  dihapus tiap stop_event_stream → vonis bandingkan detik basi vs count fresh.
  (1) Pre-check isi: dump logcat -t ${ALPHA_EVENT_PRECHECK_LINES:-100} +
  grep EVENT_TAG_PATTERN bersama reader; kosong → langsung polling
  reason=no-matching-tags. (2) start_event_stream sukses → reset
  EVENT_ON_SECS=0 + count=0 (window = sejak restart terakhir).
  (3) GAME_POLL_INTERVAL_SECS ${ALPHA_GAME_POLL_INTERVAL_SECS:-2} untuk
  paket di game map, selain itu 7 dtk biasa.
  L1: sh -n exit 0, diff --check 0, shellcheck identik baseline (tanpa
  warning baru), uji pola 10 token case+grep OK. Commit e0e3bb2 di cabang
  work/monitor-event-poll (belum merge, tanpa push).
  TUNGGU: user apply ke HP + tes (L2). PELAJARAN: klaim "ROM tak punya tag"
  wajib dibuktikan via grep log dulu sebelum menyimpulkan.

- MODUL33-STABIL-OTOMATIS (2026-09-25, leader langsung, minta user:
  PGR/WuWa pacing-cepat stutter + suhu >40C di mode perf; Alpha jadi
  stabil-otomatis minim-stutter, maximal via HSIN saja):
  UNIVERSAL tanpa hardcode angka device — lantai = % dari hw_max
  per-policy + snap-down OPP per-policy (60% big / 35% little,
  performance 35%); semua tulis guard node-ada (skip+log bila absen);
  loop semua policy (1/2/3+ cluster); GPU scan generik
  (*gpu*|*mali*|*kgsl*|*adreno*). Isi: floor 75→60% (p6 -1 rung),
  uclamp 60→45, sched extreme 40s→60/60/50/600, GPU min TIDAK
  dikunci (max saja + gov performance), kbase upthreshold 30→60,
  VM vfs 200→100, IO 4096→2048, fas-rs fast→performance.
  Gap extreme→performance mengecil = step-down 75C halus.
  L1: sh-n OK, shellcheck -S error 0, sandbox OPP T615 asli →
  extreme 614400/1040000/uclamp45/GPU-min-utuh, perf 614400/768000/
  uclamp15, balanced restore-only. Bump 32→33 modul-only (APK 20).
  Commit 54d103e. MENUNGGU: push/CI + tes HP PGR/WuWa (L2).

- B35-UNIVERSAL-GUARDS (2026-09-25, leader langsung, audit explore):
  Fix 5 temuan HIGH/MEDIUM: (1) `CPU_POLICIES` unbound di uninstall.sh
  → source `detect.sh` dulu, `gb_restore` CPU jalan; (2) AsoulOpt
  unknown-manager → `retry:` flag + return 1 → service.sh retry;
  (3) customize.sh loop var leak → subshell; (4) gameboost.sh guards
  `_gb_backup_native`/`_gb_apply_cpu`/`gb_restore` (WARN + return).
  L1: sh-n OK, shellcheck 0, sandbox 5 skenario PASS. Merge 69f914d.
  Tanpa bump versi. MENUNGGU: tes HP (L2).

- B34-ROOTEXECUTOR (2026-09-25, leader + dev-apk work/b34-roottimeout):
  kelas baru `java/.../RootExecutor.java` (timeout 20 dtk, cek exit code,
  quoting `quoteArg`); `ToolsKit.revert` pakai wrapper + toast hanya bila
  sukses. L1: CI SUCCESS 36042954181 (54s) di branch; koreksi leader
  1 baris komentar. Merge 822fadf. BELUM L2 HP.
- B33-CPUSET-TOPAPP (2026-09-25, leader + dev-modul work/b33-cpuset-topapp):
  top-app = big + 2 little pertama; foreground tetap big; background tetap
  little; topologi tak dikenal = jangan sentuh cpuset (perilaku lama).
  L1: sh-n OK, shellcheck 0, sandbox (top-app big+2 little, restore native,
  fallback little<2 + topologi-unknown SKIP). Merge 72dfb81 (tanpa bump
  versi). Push DONE + CI SUCCESS 36042556279 (46s). BELUM L2 HP.
- ZIP-SDCARD modul32 (2026-09-24): Alpha-Fusion-v32-pgr.zip (5643922
  byte, md5 49c323ab61ca9ecb8590e924d973bc49) di /sdcard/alpha/.
  Verified: versionCode=32 + floor 75% di dalam zip.
  Zip lama dibersihkan, sisa 1 file.

- MODUL32-PGR-KENCENG (2026-09-24, leader langsung, minta user: PGR
  kurang smooth, mau lebih kenceng): extreme big floor 65→75% SATU
  variabel (little 35% + uclamp60/15 + sched + VM + IO + GPU + cpuset
  + thermal 75-85-95 TAK berubah). T615 sandbox: p6 1040000→1228800
  (+2 rung), p0 tetap 614400, performance tetap 614400/768000.
  L1: bash-n OK, shellcheck -S error 0, sandbox OPP, diff 2 file
  (gameboost 8+/8- + module.prop 31→32 modul-only, APK tetap 20).
  Commit 5ad155d, push fusion-v2 DONE, CI SUCCESS 36016623318.
   DISPATCH-GAGAL dev-modul (Model not found: mimo-v2.5-free, ke-4x)
   → leader ambil alih (AGENTS p6). L2-PGR: user 2026-09-25 lapor gacor/OK. MENUNGGU L2-WuWa.
- MODUL31-TIMPA-BERSIH (2026-09-24, leader langsung, minta user: flash
  timpa tanpa uninstall, uninstall bersih juga): biang error tiap flash
  = 8x set_perm .bin yang TAK ADA di zip (hanya di zip tahap rilis) ->
  guard [ -f ]; customize bersihkan state basi saat timpa (transient +
  snapshot tanpa NATIVE_VERSION=30, game list dipertahankan); uninstall
  kill monitor+watchdog+pgr-log via cmdline + gb_restore best-effort +
  bersih total (game list dipertahankan) + wait bounded 60 dtk.
  L1: sh-n 3/3, shellcheck 0, sandbox 3/3 (cleanup, bin-guard 2a/2b,
  uninstall penuh exit 0). Bump 30->31 modul-only. DISPATCH-GAGAL
  dev-modul (mimo retired) -> leader ambil alih (AGENTS p6). MENUNGGU:
  push/CI + tes HP timpa langsung (L2).
  CI SUCCESS 35959277271.
- ZIP-SDCARD modul31 (2026-09-24, minta user "1 file fix aja"):
  Alpha-Fusion-v1.zip CI 35959277271 diunduh ke /sdcard/alpha
  (5641290-an byte, md5 45a4a556cda79f1ab65377fb1af2aa44,
  versionCode=31 terverifikasi + isi modul31 di dalam).
  Lama dibersihkan: zip v29 + isolasi-kresek.sh + 3x pre-*.bak
  dihapus -> sisa 1 file. (Isi .bak ada di git history bila perlu.)

- MODUL30-STABIL-RILIS (2026-09-24, leader langsung, keluhan "garapan ga
  stabil + rilis pun kresek"): audit 4f73ed7..HEAD = gameboost rasa-v20
  sudah sama (65/35/uclamp60-15/sched40-70/VM/IO/fas-rs/cpuset/thermal
  75-85-95); tweak nyangkut = profiles.sh 85→90/15→20/256→512 (modul22
  perf-agro tak ke-revert) + native_boost.conf sekali-tulis (snapshot
  modul23/26 ikut kebawa flash) + transient boost_level/.gb_active.
  Fix: profiles 4 angka revert v20; NATIVE_VERSION=30 paksa refresh
  snapshot basi; service.sh boot hapus transient. Floor asimetris
  modul29 dipertahankan. Bump 29→30 modul-only (APK 20).
  L1: sh-n 3/3, shellcheck 0, sandbox refresh (basi→30, rerun md5 sama).
  CI SUCCESS 35957462703.
  DISPATCH-GAGAL dev-modul: `Model not found:
  opencode/mimo-v2.5-free` (sama kayak b28) → leader ambil alih, tanpa
  ganti model (AGENTS p6). MENUNGGU: push/CI + tes HP WuWa (L2).

- ISOLASI-KRESEK (2026-09-24, tugas user, leader): Q1 = merge 2-level
  modul26 DISENGAJA (minta user, 69bcb9d). Angka user TERVERIFIKASI
  + 3 delta tambahan (sched/VM/fas-rs); koreksi GPU 85→90 = jalur
  engine bukan gameboost. HEAD sudah 3-tier lagi (sedang vs max
  terpisah). HP user masih modul26 (live versionCode=26); stune ABSEN
  = no-op. Skrip /sdcard/alpha/isolasi-kresek.sh siap. MENUNGGU: uji
  live S0-S5 dengan user (reproduksi scene + dengar kresek).

- FLOOR-ASIMETRIS modul 29 (2026-09-24, leader langsung, keluhan
  "masih ngeleg + kresek" pasca-modul28): extreme big 65% / little
  35% (T615 p6=1040000 boost utuh, p0=614400 adem); perf/balanced/
  fallback tak berubah. L1: bash-n OK, shellcheck -S error 0,
  sandbox 4/4 (extreme/perf/balanced/fallback). CI SUCCESS 35953811436.
  MENUNGGU: tes HP WuWa (L2).
- RASA-V20 modul 28 (2026-09-24, leader ambil alih): 3-tier v20 kembali

- RASA-V20 modul 28 (2026-09-24, leader ambil alih): 3-tier v20 kembali
  (extreme65/uclamp60 game + mild35/15 tangga 75C + balanced restore).
  L1: bash-n OK, shellcheck 0, sandbox 3/3, CI SUCCESS 35948936810,
  live extreme+restore persis, monitor pid 14630 INIT OK.
  MENUNGGU L2: tes WuWa user.
- DISPATCH-GAGAL dev-modul b28 (2026-09-24, leader): Task revert rasa-v20
  gagal dispatch — error persis: `Model not found: opencode/mimo-v2.5-free.
  Did you mean: mimo-v2.6-flash-free, ...`. Sesuai AGENTS p6: tanpa ganti
  model, leader ambil alih langsung. User perlu ganti model dev-modul +
  restart bila mau delegasi lagi.
- FIX-CPUFLOOR modul 27 (2026-09-24, leader live-test izin user):
  lantai CPU tak pernah apply via monitor (CPU_POLICIES kosong, 0
  baris CPU_FREQ di log WuWa 09:07). Fix 17 baris di monitor.sh
  (detected.conf + fallback + export + log INIT). L1: bash-n OK,
  shellcheck 0, sandbox 2/2, live apply 1040000/1228800 + restore
  persis, device INIT policy0 policy6 (pid 22699), CI SUCCESS run
  35947188693. MENUNGGU L2: tes WuWa user.
- MERGE-2LEVEL modul 26 (2026-09-24, leader langsung, minta user:
  extreme ga ada di aplikasi → tuning max pindah ke performance saja):
  gameboost kini 2 level — performance = ex-extreme (floor 75%
  1040000/1228800, uclamp70, stune100, sched 40/40/30/1000, VM
  40/200/10/1, IO 4096, fas-rs fast); balanced = restore-only.
  "extreme" lama jadi alias performance di _gb_level (kompat file
  lama). Monitor: target game default performance; step-down
  hangat 78C → balanced-soft (active tetap 1, cooldown <70C apply
  ulang max); 85C tetap hard-exit + apply_now balanced. uscfreq
  hold TETAP OFF. Bukti L1: bash -n 2/2, shellcheck -S error 0,
  sandbox T615 → perf 1040000/1228800/uclamp70/VM40-200, alias
  extreme identik (boost=performance), balanced restore-only,
  USCFREQ 0. MENUNGGU: push/CI + tes HP (L2).
- ZIP-SDCARD modul 26 (2026-09-24, leader): /sdcard/alpha dibersihkan
  (zip utama v23-kresek + lama/b34-floor75 + lama/modul22 dihapus atas
  perintah user) → hanya Alpha-Fusion-v1.zip (5641358 byte,
  md5 e1bf4f4dee56a95eabba50f218d24c04, versionCode=26, run
  35945175894, isi terverifikasi: alias performance|extreme 1 baris,
  floor75, monitor target performance). MENUNGGU tes HP (L2).

- REVERT-USCFREQ modul 25 (2026-09-24, leader langsung, konfirmasi user:
  "sebelum uscfreq enak, sesudah uscfreq ga enak banget"): tuning enak
  modul22 dikembalikan TANPA hold — extreme 75% (p0 1040000/p6 1228800)
  + uclamp70, performance 50% (768000/768000) + uclamp25, balanced
  90/90, perf min 20, ra 512, thermal 78C; uscfreq 5000/3000 TETAP OFF
  (backup/restore dipertahankan agar HP modul23 pulih native 1000µs).
  Bukti L1: bash -n 3/3, shellcheck -S error 0, sandbox OPP T615 →
  extreme 1040000/1228800/uclamp70 + perf 768000/768000/uclamp25 +
  USCFREQ 0 baris (restore CPU skip di sandbox minimal tanpa
  scaling_max_freq — wajar; restore on-device terbukti RC2-SYNC).
  CI modul24 SUCCESS (35944541189). MENUNGGU: push/CI modul25 + tes HP (L2).

- REVERT-STABIL modul 24 (2026-09-24, leader langsung, keluhan Unisoc
  kresek+patah): kembali ke rasa v20 stabil. gameboost extreme 75→65%
  + uclamp 70→60, performance 50→35% + uclamp 25→15; uscfreq hold
  5000/3000 DIMATIKAN (backup/restore dipertahankan agar HP modul23
  pulih native); profiles balanced 90→85 (CPU+GPU), perf min 20→15,
  ra 512→256; monitor thermal 78→75C (2 titik + log). Bump 23→24
  modul-only (APK tetap 20). Bukti L1: bash -n 3/3, shellcheck -S
  error 0, sandbox OPP T615 asli → extreme p0/p6=1040000/uclamp60,
  performance 614400/768000/uclamp15, USCFREQ 0 baris, restore native.
  MENUNGGU: push/CI + zip + tes HP (L2).

- USCFREQ-HOLD modul 23 (2026-09-24, leader, "komboin" user):
  tahan turun governor Unisoc: extreme down_rate 1000→5000µs,
  performance →3000µs, restore native (snapshot key
  <pol>_uscfreq_down_rate). work/uscfreq-hold → merge --no-ff.
  Bukti L1: bash -n OK, shellcheck 0, sandbox roundtrip
  1000→3000→1000 (perf) + 5000 (extreme) + policy tanpa
  uscfreq = 0 baris log (D7300-sugov_ext auto-skip).
  Audit MTK D7300: gov sudah performance (tak perlu sentuh),
  GPU/IO/floor sudah ke-cover; fpsgo-fbt + set_ux_uclamp =
  wilayah fas-rs → SENGAJA tak disentuh.   Terbuka: /dev/cpuctl
  di D7300 (minta `ls` ke tester).
  ZIP: run 35941796110 SUCCESS → /sdcard/alpha/Alpha-Fusion-v1.zip
  (5641290 byte, md5 404075d6859e9bf4a4c9687832f54a28,
  versionCode=23, USCFREQ 2 hook). Lama di-rename modul22.
  MENUNGGU: push/CI + zip + tes HP (L2).

- PERF-AGRO (2026-09-23, leader langsung, dev-modul masih down):
  user minta performance galak dikit + balanced naik aman + thermal
  jangan cepat step-down. Cabang work/perf-agro → merge --no-ff
  588df8a ke fusion-v2. Isi: floor perf 35→40% + uclamp 15→25
  (gameboost.sh), engine perf min 15→20 + ra 256→512, balanced
  max/GPU 85→90 (profiles.sh), step-down 75→78C di 2 titik +
  log (monitor.sh; recovery <70 + 85/95 utuh). Bump modul 22
  (version.txt/APK tetap 20). Bukti L1: bash -n 3/3 OK,
  shellcheck 0 error, sandbox sysfs palsu (40%→360000 vs
  35%→300000, mekanisme snap-down terbukti). JUJUR: floor 40%
  di T615 kemungkinan nempel rung sama (644800 vs 564200,
  snap-down ke 614400 bila rung-2 >644800) — minta OPP asli
- PERF50 (2026-09-23, leader, izin user baca device langsung):
  OPP asli T615 dibaca dari HP (tanpa su, read-only):
  p0=614400..1612000 (8 rung), p6=768000..1820000 (7 rung).
  Matematika: 40% = 644800/728000 → snap-down 614400/768000
  = SAMA PERSIS kayak 35% (perubahan kemarin NO-OP, jujur
  diakui). Floor 50% = 806000/910000 → 768000/768000:
  p0 NAIK 1 rung (+25%), p6 tetap (rung-2 p6=1040000 butuh
  ≥57.2%, sengaja tidak diambil demi rem thermal). Cabang
  work/perf50 → merge --no-ff ke fusion-v2. Bukti L1: bash -n
  OK + sandbox TABEL ASLI → p0=768000 p6=768000. Live snapshot:
  min_freq masih native (boost tidak aktif saat dicek).
  MENUNGGU: push/CI + tes HP (L2).
- ZIP-SDCARD (2026-09-23): run 35914538728 SUCCESS (kode
  perf50+modul22). Artefak Alpha-Fusion-v1 diunduh ke
  /sdcard/alpha/Alpha-Fusion-v1.zip (5640296 byte,
  md5 9cfcfa979b95c6896a440ecb9419dce) — isi terverifikasi:
  versionCode=22, floor 50%, uclamp 25. L1 LENGKAP (sandbox
  + CI hijau). MENUNGGU L2: tes HP user + tester D7300.

- FLOOR-75 (2026-09-23): dispatch dev-modul GAGAL — model
  `opencode/mimo-v2.5-free` retired ("Model not found:
  opencode/mimo-v2.5-free. Did you mean: mimo-v2.6-flash-free,
  ..."). Sesuai AGENTS p6: tanpa ganti model, leader ambil alih
  (file 1, ≤20 baris). fusion-v2 = commit floor-75 + bump 21
  (1 ahead origin). MENUNGGU: CI/package + user tes HP + L2/arsip.
  User perlu ganti model dev-modul + restart bila mau delegasi lagi.

- RILIS v1-b16-final (2026-09-21): GitHub SUDAH sinkron sebelum rilis
  (fusion-v2 = origin/fusion-v2 = 81c7955, 0 ahead/behind; release
  sebelumnya NOL). Tag `v1-b16-final` di 81c7955 + Release GitHub
  (Latest) berisi 3 aset /sdcard/alpha: zip `4a720089` + apk
  `22f033cf` (v16, cert SAMA a0698c50) + CEK_TES-b16.md — dari run
  35562535686 SUCCESS. Hapus remote tak terpakai:
  origin/work/b14-restyle-dev (merged ✓) + origin/work/final-modul
  (diganti final-modul-2; isi M1-M9 lestari di fusion-v2 via d1eb55d;
  ref lokal dipertahankan). Hapus 9 cabang lokal merged; sisa lokal:
  master + work/final-modul + work/m9-verify-qa (unmerged, arsip).
  Tanpa force push, master tak disentuh, histori tak ditulis ulang.
  Commit ini juga menyimpan AGENTS.md "Khusus Alpha" (9 baris docs,
  sebelumnya uncommitted — pelajaran: commit cepat agar tak hilang
  oleh reset pekerja).

- BUILD 16 (2026-09-21): run `35561861525` SUCCESS (gagal dulu `35561280307`:
  b9a `{p4}`→v24 invalid di fresh decode → fix `{v8}`, rebuild OK). APK
  `/sdcard/alpha/AlphaBubble-b16.apk` (`19ac2519`, 2.3M, versionCode 16 =
  version.txt, cert SAMA `a0698c50`, 9 kelas dex incl CardAlpha, 1 LAUNCHER).
  CEK_TES-b16.md 5 poin (~/work + /sdcard/alpha). BELUM tes HP. Isi:
  (1) slider "Transparansi kartu" 30–100% default 100%, live, teks terbaca;
  (2) REFRESH intent ditangani (akar: onStartCommand hanya TOGGLE; NOL field
  static scale); (3) BATAL dismiss saja, COMPILE satu-satunya pemicu (akar:
  hook lama di pemanggil openDexopt); (4) dialog dexopt gelap membulat + pill.
  Review leader: TERIMA + koreksi REV2 (sed 1-baris, ColorStateList + 2 warna
  kartu, b16c anti-VerifyError, OK pill pasca-show, step workflow b16).
  Dispatch dev-apk 4x "Task cancelled" (jaringan) tapi pekerja tetap jalan di
  background (work/b16-fix, 5 commit). Model: dev-apk tak teridentifikasi
  (Task tanpa header model); leader muse-spark-1.3-contributor-free.
  Rincian: NOTES.md § Build 16.

- FALLBACK MODEL (2026-09-21): plugin `opencode-runtime-fallback@0.2.4`
  ter-pin (exact + lock) di ~/.config/opencode; 2 kandidat ditolak
  (peva3: tanpa rantai/agent + Ralph-loop; zaplakhov: tanpa rantai +
  dep tak-pin + native sqlite). Rantai per agent + TTFT 60 dtk +
  cooldown 600 dtk di opencode.json/opencode-fallback.json. Uji:
  primer bogus → log buktikan resolvedAgent + model_not_found +
  planned→mimo; mimo jawab "OK" (15,3 dtk); agent uji dihapus.
  Tanpa bakar kuota. Rincian + pantau/mati: NOTES.md § FALLBACK.
  WAJIB user restart (server PID 3868 masih config lama).

- SERAH-TERIMA FINAL (2026-09-21): build run 35542625045 SUCCESS
  (apk-edit 35542624998 + package, 24/24 steps). Tag batch4-built
  (built, bukan tested). Artefak: ~/work/final/apk/AlphaBubble-signed.apk
  (4b25c685, 2.3M) + ~/work/final/zip/Alpha-Fusion-v1.zip (a7b779cd,
  5.6M; module.prop + META-INF + companion APK terverifikasi).
  Disalin ke /sdcard/alpha/ sebagai *-b15-final.* (b15 lama utuh).
  CEK_TES.md di ~/work/ + /sdcard/alpha/. Run terpakai: 1/10
  (+2 susulan untuk push STATE ini bila memicu). Revisi: APK 0,
  modul 1 (M3-Adreno). BLOCKED-smali: A2a live, A2h drag-tepi,
  A3b setSelected. Risiko: versionCode tetap 15 (APK b15 lama tak
  auto-update); unhandled-intent refresh menunggu hook smali.

- PEKERJAAN FINAL (2026-09-21): dev-apk work/b16-apk (c2951ab) TERIMA
  (A1 pref lama dibuang; A2 HelperGuard+intent refresh aman; A3 chip
  res60-100 + galeri pill + BgEditor tunggal; BLOCKED-smali: A2a live,
  A2h drag-tepi, A3b setSelected); dev-modul work/final-modul-2
  (ee82297) + REVISI-1 M3-Adreno GPU_MAX_FREQ (03fdf50, sandbox PASS)
  TERIMA, M1-M9 SELESAI. Merge leader 0398254 + d1eb55d tanpa konflik.
  Verifikasi: sh -n 7/7, XML 4/4, resetprop aktif NOL, secret 0,
  alpha-diag 13/13. Model: dev-apk nemotron-3-ultra-free, dev-modul
  mimo-v2.5-free, NOL 429. INSIDEN: edit leader tak-commit
  (AGENTS p6, STATE/NOTES uji-tim) terhapus reset pekerja di working
  tree bersama → diterapkan ulang + AGENTS p7 (larang checkout/reset).
  Rincian: NOTES.md § PEKERJAAN FINAL. Berikutnya: push build (1/10).

- ATURAN 429 (2026-09-21): dev kena 429/model tumbang → JANGAN ganti
  model (baru berlaku setelah restart). Hentikan item, commit WIP di
  work/<id>, tulis agent + error persis di STATE.md, lanjut item lain,
  lalu lapor; user yg ganti model + restart (AGENTS.md poin 6).

- TIM v1 SELESAI (2026-09-21): 1 leader + dev-apk + dev-modul; 12 skill di
  ~/.config/opencode/skills/ (6 superpowers + 4 proyek + 2 lama); 3 agent di
  ~/.config/opencode/agent/. Backup: ~/work/backup-opencode-20260921-0502.
  AGENTS.md baru 20 baris. Skill ditolak: NOL (6 kandidat lolos: tanpa
  unduh/eksekusi jaringan, tanpa exfil, tanpa izin luas). Uji: dev-modul
  tambah seksi TIM v1 6 baris di NOTES.md (cabang kerja → merge 77d5c7d,
  review TERIMA 0 revisi). Model: leader
  opencode/muse-spark-1.3-contributor-free; dev-apk
  openrouter/poolside/laguna-s-2.1:free; dev-modul opencode/mimo-v2.5-free
  (model-health.md tidak ada → fallback). SDD disesuaikan ke OpenCode.
  Restart opencode agar config baru terbaca. Master tak disentuh, tanpa force.

- GANTI RENCANA TANPA KOMBO (2026-09-21, DIJEDA atas permintaan user):
  Pekerjaan APK/modul DIJEDA. Tanpa sentuh perangkat (tanpa pm/su/input/screenshot/tulis /sys|/proc/reboot/flash).
  Versi v1, tanpa force push, master tidak disentuh, tanpa cetak/commit secret (API key dibaca dari config, tidak dicetak).
  Backup ~/.config/opencode SEBELUM ubah. FASE0: NOL pekerja (pgrep/locks kosong), worktree bersih
  (final-apk 0944574, final-modul c0917d9, m9-verify ce57a28), HEAD fusion-v2 5723662.
  `M AGENTS.md` BELUM diverifikasi (klaim kombo OK via curl vs GAGAL via opencode run + log 20:46 Cannot connect) — TIDAK di-commit.
  prov-riset GAGAL (researcher Alpha-fast: "Cannot connect to API: Unable to connect") +
  prov-backup GAGAL (ci Alpha-fast: sama) — putaran 1 terdokumentasi. Rencana: FASE1 daftar TANPA KOMBO,
  FASE2 uji T1/T2 via 9router (90/20/30/12 + rate 20/40 per menit), FASE3 pasang langsung ke karyawan,
  FASE4 uji tim. DIJEDA atas permintaan user.

- CHECKPOINT DIJEDA (2026-09-20 20:20, rincian ~/work/CHECKPOINT.md):
  Pekerja NOL. HEAD=8edb53a. final-apk=0944574 (A1+A3 SELESAI, A2 SEPARUH,
  review TERIMA, BELUM merge). final-modul=c0917d9 (M1,M2,M4-M7 SELESAI;
  M3+M8 koreksi direktur; M9 SEPARUH; review modul BELUM terbaca).
  Serah-terima BELUM (tag, b16, CEK_MALAM). Run: 8 terpakai.
  DIJEDA atas permintaan user, lanjutkan setelah tim siap.

- CHECKPOINT FINAL FASE 0 (2026-09-20 19:30, rincian ~/work/CHECKPOINT-final.md):
  Pekerja: NOL berjalan. HEAD=0944574. final-apk: A1+A3 SELESAI, A2 SEPARUH
  (bug toggle diperbaiki 0944574, review TERIMA; "berlaku langsung" jadi
  "berlaku saat dibuka ulang"). final-modul: M1,M2,M4-M7 SELESAI; M3 SEPARUH
  (GPU_MAX_FREQ tercatat tapi tune_gpu belum pakai); M8 SEPARUH (tanpa counter
  2x); M9 SEPARUH (sandbox 10/10 klaim pekerja; alpha-diag ditulis, tak
  dijalankan). Review M1-M9: GAGAL 3x, belum terbaca. Run: 5 terpakai.
  Serah-terima BELUM. FASE 1 rombak tim berikutnya.

- BUILD 15 (2026-09-20, TERIMA D+E, review terbaca):
  Audit b14: A1 SEBAGIAN (alpha/corner masih aktif), A2 a-c SUDAH + d BELUM
  (res60-100 mentah), A3 tombol galeri BELUM + chip SUDAH + dialog SEBAGIAN
  (radius tanpa density) + label SUDAH.
  Alur diperbaiki: brief path ABSOLUT, reviewer bash git-only (git diff/show/log
  allow, lain deny — terverifikasi), pekerja disjoint (D=java, E=XML).
  Review b14 yang GAGAL diulang TERBACA (temuan: radius tanpa density, dual key
  crop/uri, klaim ToolsKit tanpa bukti) → koreksi 1 blok (8d89df4).
  b15-d TERIMA (hapus alpha/corner apply, commit 891f126 + koreksi dead code
  7aea74e, review TERIMA); b15-e TERIMA (7 tombol pill monospace, bb27915,
  review TERIMA). Merge + bump 15 (945280d). Build 15 SUCCESS run
  `35502125769` (package) — anggaran tugas final: 2/10 run.
  APK `/sdcard/alpha/AlphaBubble-b15.apk` (`6b7c0e28...`, 2.3M) +
  ZIP `/sdcard/alpha/Alpha-Fusion-v1-b15.zip` (5.6M); b14 utuh.
  Tester 4/4 PASS statis. Worktree+cabang dihapus. BELUM tes HP. JANGAN merge master.
  Direktur: brief `~/work/tasks/b14-{bubble,restyle}.md`, 2 dev-apk paralel
  (worktree `~/work/wt/b14-{bubble,restyle}`, cabang `work/b14-*-dev`, trailer
  `Worker: dev-apk`), seleksi gabungan (konflik 1 blok di BSA diselesaikan
  manual, kedua sisi dipertahankan), merge f2a6cdb + bump 14 (2311e09).
  Build 14 SUCCESS run `35496819225`; APK `/sdcard/alpha/AlphaBubble-b14.apk`
  (`3e0fd5e4...`, 2.3M). Revisi: 0 putaran (keduanya TERIMA langsung).
  Turun tangan direktur: 1x (resolve konflik merge, ~15 baris).
  Bukti model (header log): dev-apk x2 = Alpha-think, reviewer = Alpha-think
  (gagal path), tester = Alpha-fast (PASS statis). Reviewer/tester gagal
  sebagian (path `~` + bash-deny) — direktur verifikasi sendiri (brace 65/65,
  48/48; pola OK; ver 13 sinkron sebelum bump). Worktree + cabang kerja
  dihapus. BELUM tes HP. JANGAN merge master.
  (Token konteks footer: tidak tersedia di CLI ini — tidak dicatat.)

- PERBAIKAN TIM KARYAWAN (2026-09-20, non-kode, sudah diverifikasi jalan):
  Model bawaan `9router/oc/mimo-v2.5-free`; agent plan=primary/Alpha-think;
  7 agent `~/.config/opencode/agent/*.md` mode all (think: planner/debugger/reviewer/critic,
  fast: explorer/tester/researcher); izin `external_directory ~/work/**`=allow.
  Uji: run bawaan OK, plan OK, debugger OK (Alpha-think), explorer via skrip OK
  (Alpha-fast, ISI=13), explorer ringkas 5 baris OK, reviewer temukan 2 bug ringkasan OK.
  Task-tool dalam sesi lama gagal (cache config sesi, mimo-auto) — sesi baru OK.
  Backup: `~/.config/opencode.bak-20260920-fix`. Detail tabel di NOTES.md.
  Perubahan STATE/NOTES ini BELUM di-commit (menunggu instruksi user).

- MODE DIREKTUR 2026-09-20: TAHAP 0 lolos (Alpha-think/fast + Budak ada).
  TAHAP 1 selesai (model agent, karyawan, aturan, tabel uji NOTES).
  DELEGASI GAGAL: `opencode run --agent <subagent>` → "agent is a subagent,
  not a primary agent" + model default mimo-auto Unsupported (log
  ~/work/logs/karyawan-debugger-*.log). Sesuai aturan: KERJA SENDIRI + catat.
  Semua tahap di bawah dikerjakan direktur langsung.

- Fix1 build 12 (2026-09-20): dexopt FC VerifyError TERBUKTI + DIPERBAIKI + TERVERIFIKASI HP (Canta, 89.788 dtk, dialog "Hasil dexopt", tanpa crash). Status get-compile-mode = Unknown command → fallback jujur. Screenshot b12-dexopt-done.png + dump v12-dexopt-done.xml.

- Branch: `fusion-v2` (tracking `origin/fusion-v2`). Master TIDAK disentuh sejak backup.
- HEAD: tree modul dari `Alpha-fusion-v2-final.zip` (158 file) + `.gitignore` + `AGENTS.md`.
- Backup: tag `backup-source-rebuild` → master `efaa117` (sudah push). Stash `termux-workaround-mirror-timeout` masih ada.
- Sumber zip: `/sdcard/alpha/Alpha-fusion-v2-final.zip` (md5 `6c609177a75509104aa8d402f6017ee2`).
- APK asli: `companion/AlphaBubble.apk`, sha256 `159d4e771a6f1c0bd6ac480fa4f8f780eacb87c9f646d9d33a628a4daee89b48`.
- module.prop: id=`alpha_uperf_fasrs_fusion`, version=v3, versionCode=3 (= version.txt = ALPHA_COMPANION_VER).
- Sudah diverifikasi: exec bit + LF (script bersih, hanya biner + 1 md yang mengandung CR).
- 2026-09-19: `.opencode/` disalin (AGENTS.md + agent/7 + skill/3 + command/5, 16 file, tanpa secret).
- 2026-09-19: workflow `.github/workflows/package.yml` dibuat (zip META-INF di root, exclude docs/.opencode/build-output, upload artifact). Validasi YAML lokal diskip (no pyyaml, dilarang install); run Actions yang memvalidasi.
- 2026-09-19: run `35427306606` (manual) + `35427296073` (push) → SUCCESS. Zip diunduh ke `build-output/Alpha-Fusion-v2.zip` (5.4M).
- Verifikasi: `module.prop` di root ✓, `META-INF/com/google/android/update-binary` ✓, sha256 `companion/AlphaBubble.apk` = `159d4e77...ee89b48` SAMA dengan asli ✓. Tidak ada folder pembungkus, tidak ada file exclude di dalam zip.
- 2026-09-19: bersih cache `~/.gradle` (20M) + `~/.cache` (11M). Protected (`~/.config/opencode`, `~/.config/gh`, `~/.ssh`, `~/storage`) utuh.
- 2026-09-19: cek keystore — keduanya alias `alpha`, fingerprint tak tampil tanpa password (Enter) → belum final; `.gitignore` + `keystore.properties`; git bersih dari jks.
- 2026-09-19: secret KEYSTORE_B64 + KEYSTORE_PASSWORD ada (secret lama diabaikan). Workflow `apk-edit.yml` dibuat + `apk-overlay/.gitkeep`.
- 2026-09-19: run `35428578321` GAGAL di step sign: `Unsupported option: --ks-pass:env` (build-tools 37.0.0; apktool rebuild SUKSES). Fix: password via `:file` (percobaan 1).
- 2026-09-19: run `35428651553` GAGAL juga: `Unsupported option: --ks-pass:file`. Diagnostik `--help` BT37: format benar `--ks-pass env:KS_PASS` (spasi, bukan titik-dua). Fix final (percobaan 2).
- 2026-09-19: run `35428755191` SUCCESS (rebuild tanpa perubahan). APK di `build-output/AlphaBubble-edited.apk` (2.3M): verify OK, cert baru `a0698c50…` ≠ lama, package/versionCode sama.
- 2026-09-19: sambung pipeline ke packaging — `version.txt`=2 (sumber tunggal), `package.yml` terintegrasi (decode→overlay→patch versionCode→sign→enforce→staging→zip), fix flag basi di `companion_install.sh` (uninstall→reflash).
- 2026-09-19: run `35429331531` GAGAL: `NumberFormatException: For input string: "'2'"` — apktool 3.0.3 mau versionCode TANPA kutip. Fix sed → bare number (percobaan 1).
- 2026-09-19: run `35429383410` SUCCESS tapi zip 20M — bocor `apktool.jar` root (15.5M) karena download di root. Fix: apktool ke `work/tools/` (tercover exclude `work/`).
- 2026-09-19: run `35429540702` SUCCESS. Zip final 5.4M di `build-output/`: daftar file identik asli, APK cert baru `a0698c50…`, package `com.alphabubble` versionCode 2 = version.txt = sh.
- v1 build 13 PERBAIKAN TES HP PIPELINE SUCCESS (run `35493343726`): dexopt Context signatures + status jujur + proporsional + slider + kartu + crop + pill. Bukti HP: dexopt Canta 89.788 dtk dialog "Hasil dexopt" tanpa crash (dump v12-dexopt-done.xml + b12-dexopt-done.png); BSA + RESET KE BAWAAN (b13-bsa.png); kartu BUBBLE + "Akses cepat ganti profil." (home5 + b13-homecard.png); picker terbuka (b13-picker.png) → STOP, PERLU TES MANUAL; PERALATAN + pill APPLY/RESET/DEXOPT (b13tools + b13-tools.png). Tanpa FATAL. File `/sdcard/alpha/AlphaBubble-b13.apk` (`41bec86e...`). BELUM lolos user. JANGAN merge master.
- v1 build 10 BATCH3 PIPELINE SUCCESS (run `35480723146`): C1 BubbleStyle + notif dinamis + crop UI + 7 kelas dex. Tes perangkat: STATIS SAJA (Chrome di depan, tes UI ditunda). File `/sdcard/alpha/AlphaBubble-b10.apk` + zip b10. BLOCKED: aksi profil per-item. BELUM tes user. JANGAN merge master.
- v1 build 9 BATCH2: tag `batch2-built`. File `/sdcard/alpha/AlphaBubble-b9.apk`. BLOCKED: render confirm.
- v1 build 8 BATCH1 PIPELINE SUCCESS (run `35478758890`): kartu BUBBLE Home + onboarding + guard BL + overlay kecil + hardening HelperGuard. Bukti: hook Batch1 OK, 4 kelas dex OK, versionCode 8, cert SAMA. alpha-test full install 6/7 (BubbleService mati wajar autostart off; retry hidup 7/7). Kartu BUBBLE tampil di UI dump. Zip `~/work/v8/Alpha-Fusion-v1.zip`, APK `88961b26...`, salinan `/sdcard/alpha/AlphaBubble-b8.apk` + zip. BELUM tes user. JANGAN merge master.
- v1 build 7 PIPELINE SUCCESS (run `35454848558`): 1 ikon LAUNCHER + shortcut Pengaturan Bubble + ikon notif monokrom ic_stat_alpha (0x7f05001a) + internal 7. Insiden: aapt2 tolak label shortcut literal → @string; badging tak list non-launcher activity → verify via xmltree. Zip `~/work/v7/Alpha-Fusion-v1.zip` (5.4M), APK sha256 `aa965a82...`, cert SAMA. BELUM tes HP. JANGAN merge master.
- v1 build 6 DONE PIPELINE (2026-09-19, run `35453438021` SUCCESS): BubbleSettingsActivity + nama v1 dikunci (module v1/6, APK v1/6, artifact Alpha-Fusion-v1.zip). Bukti: 2 kelas di classes5 OK, activity di manifest OK, versionCode 6, cert `a0698c50…` SAMA v3/v4/v6 (timpa tanpa uninstall). Zip `~/work/v6/Alpha-Fusion-v1.zip` (5.4M), APK sha256 `3d0da118...`. BELUM tes HP. JANGAN merge master.
- v4 DONE PIPELINE (2026-09-19, run `35451131225` SUCCESS): F2 HideFeedback (kelas Java javac+d8 → classes5.dex, hook 1 baris, VIBRATE di manifest) + B1 + bump v4. Bukti log: hook F2 OK, inject classes5.dex OK, HideFeedback di classes5.dex OK, versionCode 4, package OK. Insiden: d8 butuh mkdir output dir; sign env null (step terpisah tanpa env) → fix pisah step align+sign. Zip 5.4M `~/work/v4/Alpha-Fusion-v2.zip`, APK sha256 `fefc882b...`. BELUM tes HP. JANGAN merge master sebelum lolos HP.
- v3 DONE (2026-09-19, run `35445291496` SUCCESS): B1 Override-first regex-only (2 baris, grup unchanged) + manifest `POST_NOTIFICATIONS` + `debuggable=false` (nol dependensi debug di smali). B3 DILEWATI (tombol tanpa id). B2/F2 DITUNDA. versionCode 3 = version.txt = ALPHA_COMPANION_VER = module.prop. Zip 5.4M `~/work/v3/Alpha-Fusion-v2.zip`, APK sha256 `674df176...`. Tag `v3-tested` di `95685a2` (sumber zip, run 35445291496). Merge `fusion-v2` → `master` FF tanpa force (33 commit), master berisi modul + workflow apk-edit/decode/package (semua active). Hasil tes v3 di HP (laporan user): label resolusi benar, aplikasi normal.
- KONDISI SAAT INI (2026-09-19):
  - HEAD: `e75a3fe` (branch `fusion-v2`, sinkron dengan `origin/fusion-v2`). Working tree clean.
  - Decode ulang tersedia di `~/work/decode` (di luar repo, aman dari reboot). Jangan re-download kecuali perlu; perintah lama `/usr/tmp/opencode/decode` sudah tidak berlaku.
  - Temuan decode tercatat di NOTES.md § "Koreksi baseline dari smali APK asli" + PLAN.md § "Laporan jalur (TAHAP 2)". Rangkuman: APK = single-Activity programmatic (5040 baris smali), `BubbleService` (bukan Floating), TANPA `ProfileMonitorService`, TANPA `POST_NOTIFICATIONS`, prefs `app_bg_uri`. Game list SUDAH BENAR (`game_manager.sh` + JSON). Apply display SUDAH include density. Reset SUDAH reset keduanya. Long-press 800ms + persist `hidden` ADA (tanpa toast/vibrator). BatteryLab tanpa guard. Root tanpa timeout.
  - Jalur nyata: (a) overlay `res/`+`AndroidManifest.xml`, (b) patch smali kecil (perlu baca smali dulu), (c2) source Kotlin untuk fitur besar.
  - Pipeline terintegrasi `package.yml` berfungsi: zip v3 5.4M (`~/work/v3/Alpha-Fusion-v2.zip`), APK cert baru `a0698c50…`, package `com.alphabubble` versionCode 3 = version.txt = sh.
  - B1 DONE (Override-first), manifest overlay DONE. B3 dilewati, B2/F2 ditunda. Belum merge ke master. Flash + tes HP: OK menurut laporan user (belum ada angka label terverifikasi independen).
- b18 PERBAIKAN 3 BUG (2026-09-22, leader + dev-modul x2 + dev-apk x1): (1) game_add live merge (do_live_merge, +fix leader `&& mv` entri-terakhir) — work/b18-gamemerge abaa8ff; (2) monitor source gameboost.sh + 7 WARN log — work/b18-gbmon 1066f64; (3) cropRatio rasio-layar + bump v18 (3 file versi, +fix leader ALPHA_COMPANION_VER) — work/b18-crop 6cf73c5. Merge --no-ff x3 ke fusion-v2. Akar penyebab di NOTES.md §Build 18. CEK_TES-b18.md ditulis. Verifikasi: sandbox live add/remove + emulasi source + grep statis; build+live HP menyusul (CI + user).
- b19 RESTART FAS-RS (2026-09-22, leader + dev-modul work/b19-fasrsrestart 30235cb + koreksi leader 70fa4c4): do_live_merge killall+relaunch setelah merge sukses (flag service.sh thp 9); restart hanya bila instans berjalan. Akar penyebab (README_EN:141 next-restart) di NOTES.md §Build 19. Sandbox: PID 25606→25680. Modul-only: APK v18, module.prop 19. Merge --no-ff cccea01.
- b20 FIX RADIO + CROPRATIO (2026-09-22, leader + dev-apk x2 di work/b20-bgfix): (1) radio Fill/Fit ID unik via generateViewId + rg.check pasca-addView (508e00d, BgEditor +3/-1; akar: tanpa ID → NO_ID=-1 → eksklusivitas mati); (2) cropRatio rantai metrics decorView→WManager→Resources→Resources.getSystem + Log.w/Toast eksplisit per fallback (9ce2e31, BubbleStyle +68/-6; akar: single-source metrics + fallback rasio salah). Bump 3 file →20 (4f73ed7). Merge --no-ff 7c43a63, push → CI run 35672669126 SUCCESS (package 34s, javac+d8+sign+enforce v20). Rincian: NOTES.md §Build 20. Verifikasi HP: CEK_TES-b20.md.

- MTK UNIVERSAL RC1 (2026-09-22, leader + dev-modul T1-T4, BELUM RILIS):
  fusion-v2 = ed092b7 (3 merge --no-ff: T1 detect, T2 apply, T3 thermal +
  commit feat(mtk) customize/README/NOTES). Sandbox 70/70 PASS, rerun
  independen leader IDENTIK (sbx-mtk/full_output.txt + rerun-leader.txt).
  Stage rel-v1 dari HEAD: 8 .bin fresh via shc 4.0.3 (AArch64, game_add
  smoke OK) + stub, ziplist IDENTIK dengan FINAL lama, README MTK jujur
  (sandbox-only, legacy belum didukung), APK sha256 SAMA 159d4e77....
  RC1 zip `059341fa` di /sdcard/alpha/Alpha-Fusion-v1-release-clean-RC1.zip
  + monitor-b23final.bin (55200). Push fusion-v2 DONE (lihat bawah).
  BLOCKED: (1) user tes HP b23 ELF (ikut TESTING.md rel-v1), (2) setelah
  lolos → tag v1.0.0 + GitHub Release + public. Tanpa force push.

- T5 THERMAL-SAFETY FIX (2026-09-22, leader, BELUM RILIS):
  fusion-v2 HEAD = 38c089d (merge T5 thermal-safety). Bug: _gb_level()
  hanya mengenali performance → thermal safety ≥85C menulis balanced →
  jatuh ke extreme → device tetap max saat seharusnya pendingin.
  Fix: _gb_level() case eksplisit 3 nilai + default balanced (fail-safe);
  gb_apply() level balanced = restore-native + return awal; monitor.sh
  game-open non-forced tulis extreme eksplisit + log level dari
  boost_level. Unit test 6/6 PASS (performance/balanced/extreme/absent/garbage/caps).
  Sandbox 4/4 PASS (balanced→restore native, extreme→floor 65%,
  perf→floor 35%, absent→fail-safe balanced). Monitor snippet 3/3 PASS.
  RC2 zip: 491d3b17, ~/storage/shared/alpha/Alpha-Fusion-v1-release-clean-RC2.zip.
  MENUNGGU: (1) user tes HP b23 + thermal safety (ganti monitor.bin), (2) tag v1.0.0 + release + public.

- ON-DEVICE THERMAL TEST (2026-09-22, leader langsung di HP itel P671L
  ums9230, root): monitor.bin RC2 (1118cce8) + debug THERMAL-DBG
  (ba66c551) dipasang sementara, dikembalikan ke RC2 sesudahnya.
  HASIL: (1) periodic safety_check jalan tiap ~15s saat .gb_active=1
  (47-49°C real). (2) bind-mount fake 86000 dari namespace Termux
  TIDAK terlihat monitor (baca tetap ~45°C) → WAJIB via `su -M`
  (mount-master). (3) Dengan fake terlihat: THERMAL-DBG temp=86000 →
  `HIGH TEMP: 86000mC >= 85000, forced balanced` → gb_restore +
  apply_now balanced, .gb_active=0, scaling tetap native
  (614400/768000). (4) gb_apply-balanced T5 (copy fixed di /sdcard,
  device gameboost.sh masih pra-T5!) → restore-only, tanpa lantai
  extreme, boost_level=balanced. REVERT TOTAL: fake umount (41880
  real), profile battery, fas-rs powersave, file uji dihapus,
  monitor RC2 restart PID 30579. PENDING: flash RC2 penuh
  (gameboost.sh T5 belum live di HP).

- RC2-SYNC + OPEN/CLOSE TEST (2026-09-22, leader, tanpa reboot/game):
  3 file RC2 (gameboost/engine/detect.sh, md5 cocok) disalin ke modul
  (backup di /sdcard/alpha/pre-rc2sync/), monitor restart PID 11311.
  OPEN (extreme): p0 614400→1040000, p6 768000→1040000,
  gpu 384M→850M, boost_level=extreme, fas-rs powersave→fast. CLOSE
  (restore): semua kembali native + powersave + active=0.
  KOREKSI CATATAN: lantai boost pakai _alpha_opp_cap_pick (OPP
  terbesar ≤ target, TIDAK pernah lampaui %); snap-nearest sejati
  hanya di engine (profile max). Klaim laporan MTK soal "snap di
  boost" salah — p6=1040000 BENAR (cap-≤ dari 1183000), bukan bug.
  Device kini setara RC2 penuh. TINGGAL: perintah rilis dari user.

- RILIS v1.0.0 (2026-09-22): rilis pagi (zip FINAL lama) diganti total:
  asset kini RC2 `Alpha-Fusion-v1-release-clean.zip` (5721270, md5
  491d3b17), catatan dipangkas ke 6 baris. Tag lokal konflik dihapus.
  SISA USER: Public repo.

- REBUILD APK v20 HIJAU (2026-09-22, leader): secret signing di Alpha
  hilang total (daftar kosong) → semua run fusion-v2 merah di
  Align+sign. Repo Alpha-Old masih punya secret + run hijau (bukti
  pasangan benar). User isi ulang KEYSTORE_PASSWORD + KEYSTORE_B64
  (file alpha-release.jks SALAH → "password incorrect"; ganti ke
  ~/keys/alpha-new.jks → run 35729531470 SUCCESS 34 dtk).
  PELAJARAN: ada 2 keystore (alpha-release.jks 07:22 vs
  alpha-new.jks 14:05); yang cocok password = alpha-new.jks.
  HASIL: AlphaBubble-signed.apk versionCode=20 (CN=Alpha Control),
  ZIP 5639313 (md5 a2346d6a) = APK identik di dalam; rilis v1.0.0
  di-upload ulang + salinan di /sdcard/alpha/Alpha-Fusion-v1.zip.

- PUBLIK + RILIS FINAL (2026-09-22, leader, perintah user):
  repo Alpha PRIVATE→PUBLIC (hygiene dicek dulu: riwayat + file
  bersih dari jks/keystore/password). Rilis v1.0.0 diunduh ulang
  dan dicek: module.prop v20, APK v20 (CN=Alpha Control),
  update-binary/service.sh/customize/uninstall ada, sintaks
  gameboost+monitor OK, md5 rilis = sdcard (a2346d6a).

- PERF-MAX + BALANCED-ADEM (2026-09-25, leader + dev-modul work/perf-balanced 8f5eec1 + koreksi leader): performance raw-power (floor 50%/big75, uclamp60, sched40s, kbase30, adreno-up35, fast, gate software 95C, tangga monitor 85/90 saat manual=performance, kritis 95 tetap) + balanced adem-stabil (floor 25%, kbase 2/55, mild uclamp30/sched60s). L1: bash-n OK, shellcheck -S error 0, sandbox + uji tier 10/10. Merge --no-ff ba16cd7 ke fusion-v2, tanpa bump versi. L2: TUNGGU tes HP user.

- HYBRID-V35-FLOORS (2026-09-25, leader langsung work/perf-hybrid 62d9abc): adopsi bagian bagus v35 (extreme big 80%/little 45%, mild 40%, tap 55%/balanced 30%) di atas basis perf-max (GPU galak kbase30, gate 95C, tangga sadar-profil, sched agresif, fas-rs fast). Yang TIDAK diambil: tangga flat 82, kbase 60, uclamp/sched kalem. L1: bash-n OK, shellcheck 0, hitung OPP valid. Merge --no-ff 6325238. L2: TUNGGU tes HP user.

- ANTISNAPSHOT-V35 (2026-09-26, leader langsung, izin user audit live):
  Audit read-only HP (ums9230 T615): native_boost.conf KERACUNAN —
  policy0 min=1612000 (=max, hrsnya 614400), policy6 min=1820000
  (=max, hrsnya 768000), gpu max=384M (=min, hrsnya 850M). Akibat:
  tiap restore kunci CPU min=max (panas idle 48C) + GPU max=384M
  (FPS ketahan bawah) = "enak tapi kureng tahan 30fps". Koreksi
  .gb_active: file isi "0" = INACTIVE (bukan stale, cek monitor.sh).
  Fix repo (common/gameboost.sh, +24/-2): backupfallback CPU min ke
  cpuinfo_min bila min==max + GPU max ke rung tabel tertinggi bila
  max<=min + NATIVE_VERSION 30->31 (paksa refresh). Bump 34->35
  modul-only (APK 20). L1: bash-n OK, shellcheck -S error 0,
  sandbox racun->bersih PASS (614400/768000/850M, rerun idempoten).
  Zip: /sdcard/alpha/Alpha-Fusion-v35-antisnapshot.zip (5.4M, md5
  b02fcdf3, versionCode=35, ekstrak ulang perms OK + sh-n OK).
  Commit be894ab. L2: TUNGGU flash + reboot + tes HP.

- FINAL-V36-UNIVERSAL (2026-09-26, perintah user: balance=hybrid dinaikin,
  perf=merged pacing rata, mitigasi loading lama, semua device/chipset):
  Isi (3 file, commit 5195c3c): profiles.sh Balanced CPU min 30->35% +
  GPU floor Battery 0 / Balanced 40 / Performance 90 (+ loader
  GPU_FREQ_FLOOR_PERCENT); engine.sh blok floor lock Mali di
  tune_gpu_mali (% + snap OPP + skip node absen; Adreno sengaja cap
  saja); battery floor 0 = tulis rung terbawah (LEPAS kunci, bukan
  skip — fix bug v36-merged); thermal gate floor (balanced lepas
  >=85C, performance >=95C; HW proteksi utuh). Termasuk antisnapshot
  v31 (be894ab). Bump 35->36 modul-only (APK 20).
  L1: bash-n OK, shellcheck -S error 0, sandbox tabel T615 6/6
  (perf768M/bal384M/batt384/max-cap/skip-panas/skip-hangat/release).
  Zip: /sdcard/alpha/Alpha-Fusion-v36-final.zip (5.4M, md5
  11add594, vCode 36, ekstrak perms OK + sh-n OK). L2: TUNGGU flash
  + reboot + tes HP (game berat + bagian loading lama).
  JUJUR loading: deteksi loading tak bisa universal (tanpa akses
  FPS/game-state) — mitigasi = thermal gate + saran balanced buat
  sesi story/loading berat.

- ADAPTIVE-FLOOR-PROTOTIPE (2026-09-26, perintah user "coba aja", dev-modul
  work/adaptive-floor c564783, diverifikasi independen oleh leader):
  Isi: agf_tick + 9 helper di common/monitor.sh SAJA (+340/-0),
  hook sesudah check_gb_grace_period di 2 loop. Desain: delta
  trans_stat -> busy% -> tier HIGH/MID/LOW (70/30, MID=60% plafon),
  naik langsung + turun 3 tick + thermal paksa LOW; plafon = floor
  profil dibaca live dari profiles.sh; battery OFF; node absen/RO =
  SKIPPED sekali. L1 leader: bash-n OK, shellcheck -S error 0,
  tanpa TODO/stub, API nyata semua (gb_safety_check/GB_HIGH_THR/
  get_manual_profile), sandbox worker di-run ulang leader: 24 PASS
  0 FAIL. Asumsi kolom trans_stat TERVERIFIKASI cocok bacaan live
  T615 (* = freq aktif, kolom akhir time ms). BELUM: end-to-end
  vs gb_restore di perangkat; BELUM merge fusion-v2; BELUM zip uji.
  L2: butuh keputusan user (kemas zip uji + flash, atau revisi).

- ADAPTIVE-FLOOR HP-TEST (2026-09-26, leader + izin user test device):
  Tes live HP T615 (ums9230) via bundle extracted functions (tidak
  ganggu daemon produksi). Hasil:
  - Parser trans_stat BENAR: tick 1 baseline (total=20.3Mms low=5.5Mms),
    tick 2 busy=72% (GPU render UI walau "idle") → tier HIGH benar.
  - Thermal override BENAR: ambang turun ke 50C → tier paksa LOW + min
    384M + log `[GAMEBOOST] GPU_AGF: temp ... tier dipaksa LOW` +
    `[APPLIED] min_freq=384M`.
  - Battery profile BENAR: adaptive OFF (return 0, no baseline/tier/write/log).
  - End-to-end floor naik: max_freq manual 850M → tick 1 baseline, tick 2
    HIGH → target 768M → **APPLIED** (min 384M→768M, max 850M).
  - Respek plafon profil: battery max_freq=384M → target capped 384M
    (tak bisa min > max); performance max=850M → floor naik 768M.
  - Hysteresis: naik langsung, turun butuh 3 tick LOW berturut (tes
    sandbox PASS; HP "idle" tetap 72% busy = UI render = HIGH benar).
  - Semua L1 sandbox (24/24) + device tests (parser, thermal, battery,
    plafon, end-to-end naik) PASS. `monitor.sh` bash-n/shellcheck 0.
  Commit `a3d8e39` di `work/adaptive-floor`. BELUM merge fusion-v2;
  BELUM zip uji; L2: keputusan user (merge + zip, atau revisi ambang/
  hysteresis).

- ZIP-V37-ADAPTIVE (2026-09-26, perintah user "ya taruh di sdcard/alpha"):
  Merge work/adaptive-floor -> fusion-v2 (3ea3fe9, --no-ff, 1 file
  +415) + bump 36->37 modul-only (d3cde1a, APK 20). L1 ulang
  pasca-merge: bash-n OK, shellcheck 0. Zip:
  /sdcard/alpha/Alpha-Fusion-v37-adaptive.zip (5.4M, md5 f9278920,
  vCode 37, GPU_AGF 13x di dalam, ekstrak perms OK + sh-n 4 file
  OK). BELUM push GitHub. L2: flash + reboot + main game, rasain
  (tempur mulus? loading adem? panas wajar?).
