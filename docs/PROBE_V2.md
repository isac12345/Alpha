# PROBE v2 — cek node NET / Memory-ZRAM / Storage-IO (read-only)

## Tujuan

Memetakan node target tweak **sebelum** ada tulisan apa pun ke
`/proc` atau `/sys`. Skrip `common/probe_v2.sh` **hanya membaca**
(`test -e/-r/-w` + `cat`): tanpa tulis node, tanpa ubah izin file,
tanpa perintah sysctl penulis, tanpa operasi swap.

Node baru v2 (belum ada di `common/gameboost.sh`):
`net/core/rmem_max`, `net/core/wmem_max`, `net/ipv4/tcp_low_latency`,
`zram0/comp_algorithm`, `vm/dirty_expire_centisecs`, dan pemilihan
congestion-control berprioritas (**bbr**, lalu **cubic**, lalu cc aktif).

Sudah ditangani gameboost.sh (dicatat saja, jangan diduplikasi):
`vm/swappiness`, `vm/dirty_ratio`, `vm/dirty_background_ratio`,
`queue/read_ahead_kb`, `net/ipv4/tcp_congestion_control` (bbr-only).

## Cara jalan di HP (root, output ke /sdcard)

Dari PC:

```sh
adb push common/probe_v2.sh /data/local/tmp/probe_v2.sh
adb shell su -c 'sh /data/local/tmp/probe_v2.sh' > /sdcard/probe_v2.txt
adb pull /sdcard/probe_v2.txt
```

Atau dari Termux di HP (sudah ada Magisk/root):

```sh
su -c 'sh /data/local/tmp/probe_v2.sh' > /sdcard/probe_v2.txt
```

**Penting — jalankan sebagai root.** Tanpa root semua node milik root
(0644) akan terbaca tetapi kolom `writable=N`, itu bukan berarti node
tak bisa ditulis module (module jalan sebagai root). `writable=N`
saat *dijalankan root* = alasan SKIP yang akan dipakai tweak v2,
persis pola `_gb_write` di gameboost.sh.

Lampirkan isi `/sdcard/probe_v2.txt` (atau salin tabel di bawah)
saat lapor ke leader.

## Tabel hasil — kosong, siap isi dari output probe

Salin kolom dari baris detail
`[OK|SKIP:...] node=... exists=... readable=... writable=... value=... options=...`
dan baris ringkasan `node|default|opsi|writable`.

| Kategori | Node | Sudah di gameboost? | exists | readable | writable | default | opsi | status |
|---|---|---|---|---|---|---|---|---|
| NET | net/ipv4/tcp_congestion_control | YA (bbr-only) | | | | | | |
| NET | net/ipv4/tcp_available_congestion_control | YA (dibaca utk cek bbr) | | | | | | |
| NET | net/core/rmem_max | **BARU** | | | | | | |
| NET | net/core/wmem_max | **BARU** | | | | | | |
| NET | net/ipv4/tcp_low_latency | **BARU** | | | | | | |
| MEM | vm/swappiness | YA | | | | | | |
| MEM | zram0/comp_algorithm | **BARU** | | | | | | |
| MEM | vm/dirty_ratio | YA | | | | | | |
| MEM | vm/dirty_background_ratio | YA | | | | | | |
| IO | sda/queue/read_ahead_kb (per device utama) | YA | | | | | | |
| IO | vm/dirty_expire_centisecs | **BARU** | | | | | | |
| — | cc_pick (prioritas bbr, cubic, aktif) | **BARU** | — | — | — | (cc_active) | (cc_available) | — |

Salin mentah ringkasan probe (tempel di sini):

```text
node|default|opsi|writable
```

## Uji sandbox (dev)

Fake-fs + 4 skenario (normal, zram read-only, tcp tak-writable, node
absen) ada di `sandbox/test-v2-nodes.sh` — hanya menyentuh `$TMPDIR`,
tidak pernah `/proc` atau `/sys` asli:

```sh
sh sandbox/test-v2-nodes.sh
```
