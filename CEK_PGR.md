# CEK_PGR — Panduan Cek Performa Game (A/B Test)

1. Aktifkan log: `pgr-log start` (daemon, CSV ke /sdcard/alpha/game-log.csv).
2. Main game yang bermasalah sampai terjadi stutter/freeze.
3. Snapshot Alpha (bandingkan snap-hsin-extreme.txt sebelum/sesudah).
4. Kalau aneh: `touch /data/adb/alpha/NO_CPUSET` lalu ulangi test.
5. Masih aneh: `touch /data/adb/alpha/GAMEBOOST_NO_VM` lalu ulangi test.
6. Pembanding: `touch /data/adb/alpha/DISABLE_GAMEBOOST` (tanpa modul).
7. Hentikan log: `pgr-log stop`.
8. Kirim game-log.csv + alpha.log bila freeze terjadi.
