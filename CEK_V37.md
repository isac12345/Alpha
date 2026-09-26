# CEK-V37 — verifikasi adaptif pasca-flash + reboot (vCode 37)

Jalankan via `su -c "<perintah>"` di Termux. Semua read-only.

## 1. Modul + kode adaptif masuk?
```sh
su -c "grep versionCode /data/adb/modules/alpha_uperf_fasrs_fusion/module.prop; grep -c GPU_AGF /data/adb/modules/alpha_uperf_fasrs_fusion/common/monitor.sh"
```
Harapan: `versionCode=37`, count ≥ 10.

## 2. Snapshot racun kebuang + capture bersih?
```sh
su -c "grep -E 'NATIVE_VERSION|scaling_min_freq|gpu_.*(max|min)_freq' /data/adb/alpha/native_boost.conf"
```
Harapan: `NATIVE_VERSION=31`, `policy0 min=614400` (bukan 1612000),
`policy6 min=768000` (bukan 1820000), `gpu max=850000000` (bukan 384M).

## 3. Adaptif jalan? tier apa?
```sh
su -c "grep GPU_AGF /data/adb/alpha/alpha.log | tail -n 15"
```
Harapan: ada baris `baseline disimpan` (tick pertama) lalu
`APPLIED ... tier=HIGH/MID/LOW`. Kosong = belum ada game dibuka
(adaptif cuma jalan pas boost aktif) atau boost tak aktif.

## 4. GPU live + suhu idle
```sh
su -c "cat /sys/class/devfreq/23100000.gpu/min_freq; cat /sys/class/devfreq/23100000.gpu/max_freq; cat /sys/class/devfreq/23100000.gpu/governor; cat /data/adb/alpha/current_state; for z in /sys/class/thermal/thermal_zone*; do echo \"$(cat $z/temp 2>/dev/null) $(cat $z/type 2>/dev/null)\"; done | sort -nr | head -n 5"
```

## L2 game (setelah main 10-15 mnt)
Kirim: rasa (tempur mulus? loading adem? panas wajar?) + output
perintah no. 3 + suhu tertinggi saat main.
