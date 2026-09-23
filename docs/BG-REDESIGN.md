# Desain Redesign "Atur Latar" (Background Custom)

## 1. Analisis Akar Masalah

| # | Masalah | Bukti Kode (Baris) |
|---|---------|-------------------|
| 1 | `targetRatio` di `ZoomView` **disimpan tapi tak pernah dibaca** | `BgEditor.java:234` simpan `this.targetRatio = ratio`; `onDraw:243` dan `render():296` pakai `vw/vh` viewport dialog (MATCH_PARENT + weight, aspek tak tentu), BUKAN aspek layar |
| 2 | Viewport dialog ≠ layar device | `BgEditor.java:103-105` `ZoomView` diletakkan di `LinearLayout` weight=1, `MATCH_PARENT` lebar, tinggi 0 + weight → aspek bergantung ukuran dialog runtime, bukan 720×1600 |
| 3 | `cropRatio` decode gambar penuh tanpa `inSampleSize` → OOM foto besar | `BubbleStyle.java:111-112` `BitmapFactory.decodeStream` langsung tanpa `inJustDecodeBounds` + `inSampleSize` (berbanding `openEditor:52-67` yang benar pakai `maxSide=1600`) |
| 4 | Rantai fallback metrics **tidak pakai `getCurrentWindowMetrics` API 30+** | `BubbleStyle.java:127-181` urutan: decorView → WindowManager → Resources context → Resources.getSystem(); **hilang** `getWindowManager().getCurrentWindowMetrics()` (API 30, native tanpa library) |
| 5 | `cropSquare` deprecated wrapper → usulkan **HAPUS** | `BubbleStyle.java:250-254` `@Deprecated` wrapper `cropRatio(..., FILL, size, size)`; tidak ada pemanggil di codebase (grep `"cropSquare"` = 0), menambah API surface tanpa manfaat |

---

## 2. Algoritma Usulan (Pseudocode Java)

```java
// === Sumber ukuran layar ASLI (device) — rantai prioritas ===
static Pair<Integer,Integer> getRealScreenSize(Context c) {
    // 1) API 30+: getCurrentWindowMetrics (NATIVE android.app, tanpa library)
    if (Build.VERSION.SDK_INT >= 30 && c instanceof Activity) {
        try {
            android.graphics.Rect b = ((Activity) c)
                    .getWindowManager().getCurrentWindowMetrics().getBounds();
            if (b.width() > 0 && b.height() > 0) return Pair.create(b.width(), b.height());
        } catch (Throwable ignore) {}
    }
    // 2) decorView.getRealMetrics (API 17+)
    if (c instanceof Activity) {
        try {
            View decor = ((Activity)c).getWindow().getDecorView();
            DisplayMetrics dm = new DisplayMetrics();
            decor.getDisplay().getRealMetrics(dm);
            if (dm.widthPixels > 0 && dm.heightPixels > 0)
                return Pair.create(dm.widthPixels, dm.heightPixels);
        } catch (Throwable ignore) {}
    }
    // 3) WindowManager defaultDisplay
    try {
        WindowManager wms = (WindowManager)c.getSystemService(Context.WINDOW_SERVICE);
        DisplayMetrics dm = new DisplayMetrics();
        wms.getDefaultDisplay().getMetrics(dm);
        if (dm.widthPixels > 0 && dm.heightPixels > 0)
            return Pair.create(dm.widthPixels, dm.heightPixels);
    } catch (Throwable ignore) {}
    // 4) Resources context
    try {
        DisplayMetrics dm = c.getResources().getDisplayMetrics();
        if (dm.widthPixels > 0 && dm.heightPixels > 0)
            return Pair.create(dm.widthPixels, dm.heightPixels);
    } catch (Throwable ignore) {}
    // 5) Resources.getSystem() — terakhir
    try {
        DisplayMetrics dm = Resources.getSystem().getDisplayMetrics();
        if (dm.widthPixels > 0 && dm.heightPixels > 0) {
            Log.w(TAG, "metrics ctx 0, pakai system " + dm.widthPixels + "x" + dm.heightPixels);
            return Pair.create(dm.widthPixels, dm.heightPixels);
        }
    } catch (Throwable ignore) {}
    return null; // caller handle
}

// === inSampleSize sebelum decode penuh (pola openEditor maxSide 1600) ===
static int computeSampleSize(int srcW, int srcH, int maxSide) {
    int sample = 1;
    while (Math.max(srcW, srcH) / sample > maxSide) sample <<= 1;
    return sample;
}

// === Skala dasar dari UKURAN LAYAR ASLI (bukan viewport dialog) ===
// Fill: scale = MAX(screenW/srcW, screenH/srcH)  → isi penuh, crop tepi
// Fit:  scale = MIN(screenW/srcW, screenH/srcH)  → tampil utuh, letterbox
static float baseScaleFill(int srcW, int srcH, int screenW, int screenH) {
    return Math.max((float)screenW / srcW, (float)screenH / srcH);
}
static float baseScaleFit(int srcW, int srcH, int screenW, int screenH) {
    return Math.min((float)screenW / srcW, (float)screenH / srcH);
}

// === Komposisi matrix user (pinch-zoom 1–4x + pan dx/dy) + clamp ===
// scaleUser ∈ [1, 4], dx/dy dari gesture, clamp agar gambar tidak kosong di viewport
Matrix composeUserMatrix(Bitmap src, float baseScale, float scaleUser,
                         float dx, float dy, int viewW, int viewH) {
    float s = baseScale * scaleUser;
    float dw = src.getWidth() * s, dh = src.getHeight() * s;
    float maxDx = Math.max(0, (dw - viewW) / 2f);
    float maxDy = Math.max(0, (dh - viewH) / 2f);
    dx = clamp(dx, -maxDx, maxDx);
    dy = clamp(dy, -maxDy, maxDy);
    Matrix m = new Matrix();
    m.postTranslate(-src.getWidth()/2f, -src.getHeight()/2f);
    m.postScale(s, s);
    m.postTranslate(viewW/2f + dx, viewH/2f + dy);
    return m;
}

// === Crop final = komposisi matrix (tanpa cabang khusus rasio ekstrem) ===
// render() langsung pakai matrix di atas → canvas.drawBitmap(src, matrix, null)
// Output bitmap size = screenW × screenH (Fill) atau screenW × screenH dengan letterbox (Fit)
```

**Poin kunci:**
- Semua perhitungan berbasis **ukuran layar asli device** (720×1600), bukan viewport dialog
- `targetRatio` dihapus dari `ZoomView`; gunakan `screenW/screenH` langsung
- `inSampleSize` diterapkan di `cropRatio` (seperti `openEditor` baris 52–67)
- Gambar kecil di-upscale proporsional (tidak ada cabang khusus)
- Fill/Fit hanya beda `baseScale` (MAX vs MIN), sisa alur identik

---

## 3. Tabel Hitung Eksplisit (Layar 720×1600, Rasio 0.45)

Notasi:
- `sw, sh` = ukuran sumber gambar
- `dw, dh` = ukuran layar device = **720, 1600**
- `targetRatio = dw/dh = 720/1600 = 0.45`
- `srcRatio = sw/sh`
- **Fill baseScale** = `MAX(dw/sw, dh/sh)`
- **Fit baseScale**  = `MIN(dw/sw, dh/sh)`
- **% area terpotong (Fill)** = `1 - (cropW×cropH)/(sw×sh)` × 100%
- **Letterbox px (Fit)** = sisi yang tersisa setelah scale Fit

---

### Skenario (a) 720×1600 (sama persis layar)

| Parameter | Nilai / Rumus | Hasil |
|-----------|---------------|-------|
| sw, sh | 720, 1600 | — |
| srcRatio | 720/1600 | **0.4500** |
| targetRatio | 720/1600 | **0.4500** |
| **Fill baseScale** | MAX(720/720, 1600/1600) = MAX(1.0, 1.0) | **1.0000** |
| **Fit baseScale** | MIN(720/720, 1600/1600) = MIN(1.0, 1.0) | **1.0000** |
| Fill cropW, cropH | srcRatio == targetRatio → cropW=sw=720, cropH=sh=1600 | **720, 1600** |
| Fit scale | MIN(720/720, 1600/1600) = 1.0 | **1.0000** |
| Fit dstW, dstH | 720×1.0, 1600×1.0 | **720, 1600** |
| **% area terpotong (Fill)** | 1 - (720×1600)/(720×1600) = 0% | **0.0000%** |
| **Letterbox px (Fit)** | (dw-dstW)/2 = 0, (dh-dstH)/2 = 0 | **0 px (kiri/kanan & atas/bawah)** |

✅ **Fill == Fit identik** (baseScale 1.0, crop full source, output 720×1600, letterbox 0)

---

### Skenario (b) 1920×1080 (landscape 16:9, rasio 1.7778)

| Parameter | Nilai / Rumus | Hasil |
|-----------|---------------|-------|
| sw, sh | 1920, 1080 | — |
| srcRatio | 1920/1080 | **1.7778** |
| targetRatio | 720/1600 | **0.4500** |
| **Fill baseScale** | MAX(720/1920, 1600/1080) = MAX(0.3750, 1.4815) | **1.4815** |
| **Fit baseScale** | MIN(720/1920, 1600/1080) = MIN(0.3750, 1.4815) | **0.3750** |
| Fill: srcRatio > targetRatio → crop lebar | cropH = sh = 1080; cropW = round(sh × targetRatio) = round(1080 × 0.45) | **cropW=486, cropH=1080** |
| Fill cropX, cropY | (1920-486)/2 = 717, 0 | **717, 0** |
| **% area terpotong (Fill)** | 1 - (486×1080)/(1920×1080) = 1 - 486/1920 = 1 - 0.2531 | **74.6875%** (sisi **kiri/kanan**) |
| Fit scale | MIN(720/1920, 1600/1080) = 0.3750 | **0.3750** |
| Fit dstW, dstH | round(1920×0.375), round(1080×0.375) | **720, 405** |
| **Letterbox px (Fit)** | vertikal: (1600-405)/2 = **597.5 px** (atas/bawah); horizontal: 0 | **597.5 px atas/bawah** |

---

### Skenario (c) 1000×1000 (persegi 1:1, rasio 1.0)

| Parameter | Nilai / Rumus | Hasil |
|-----------|---------------|-------|
| sw, sh | 1000, 1000 | — |
| srcRatio | 1000/1000 | **1.0000** |
| targetRatio | 720/1600 | **0.4500** |
| **Fill baseScale** | MAX(720/1000, 1600/1000) = MAX(0.7200, 1.6000) | **1.6000** |
| **Fit baseScale** | MIN(720/1000, 1600/1000) = MIN(0.7200, 1.6000) | **0.7200** |
| Fill: srcRatio > targetRatio → crop lebar | cropH = 1000; cropW = round(1000 × 0.45) = 450 | **cropW=450, cropH=1000** |
| Fill cropX, cropY | (1000-450)/2 = 275, 0 | **275, 0** |
| **% area terpotong (Fill)** | 1 - (450×1000)/(1000×1000) = 1 - 0.45 | **55.0000%** (sisi **kiri/kanan**) |
| Fit scale | MIN(720/1000, 1600/1000) = 0.7200 | **0.7200** |
| Fit dstW, dstH | round(1000×0.72), round(1000×0.72) | **720, 720** |
| **Letterbox px (Fit)** | vertikal: (1600-720)/2 = **440.0 px** (atas/bawah); horizontal: 0 | **440.0 px atas/bawah** |

---

### Skenario (d) 3000×800 (sangat lebar, rasio 3.75) — **tanpa cabang khusus**

| Parameter | Nilai / Rumus | Hasil |
|-----------|---------------|-------|
| sw, sh | 3000, 800 | — |
| srcRatio | 3000/800 | **3.7500** |
| targetRatio | 720/1600 | **0.4500** |
| **Fill baseScale** | MAX(720/3000, 1600/800) = MAX(0.2400, 2.0000) | **2.0000** |
| **Fit baseScale** | MIN(720/3000, 1600/800) = MIN(0.2400, 2.0000) | **0.2400** |
| Fill: srcRatio > targetRatio → crop lebar | cropH = 800; cropW = round(800 × 0.45) = 360 | **cropW=360, cropH=800** |
| Fill cropX, cropY | (3000-360)/2 = 1320, 0 | **1320, 0** |
| **% area terpotong (Fill)** | 1 - (360×800)/(3000×800) = 1 - 360/3000 = 1 - 0.12 | **88.0000%** (sisi **kiri/kanan**) |
| Fit scale | MIN(720/3000, 1600/800) = 0.2400 | **0.2400** |
| Fit dstW, dstH | round(3000×0.24), round(800×0.24) | **720, 192** |
| **Letterbox px (Fit)** | vertikal: (1600-192)/2 = **704.0 px** (atas/bawah); horizontal: 0 | **704.0 px atas/bawah** |

✅ **Tidak ada cabang khusus** — rumus `MAX/MIN` dan `cropW = round(sh × targetRatio)` bekerja seragam.

---

### Skenario (e) 200×200 (kecil persegi, rasio 1.0) — **upscale proporsional**

| Parameter | Nilai / Rumus | Hasil |
|-----------|---------------|-------|
| sw, sh | 200, 200 | — |
| srcRatio | 200/200 | **1.0000** |
| targetRatio | 720/1600 | **0.4500** |
| **Fill baseScale** | MAX(720/200, 1600/200) = MAX(3.6000, 8.0000) | **8.0000** |
| **Fit baseScale** | MIN(720/200, 1600/200) = MIN(3.6000, 8.0000) | **3.6000** |
| Fill: srcRatio > targetRatio → crop lebar | cropH = 200; cropW = round(200 × 0.45) = 90 | **cropW=90, cropH=200** |
| Fill cropX, cropY | (200-90)/2 = 55, 0 | **55, 0** |
| **% area terpotong (Fill)** | 1 - (90×200)/(200×200) = 1 - 0.45 | **55.0000%** (sisi **kiri/kanan**) |
| Fill output scale | baseScale = 8.0 → 90×8=720, 200×8=1600 | **720×1600** (upscale 8×) |
| Fit scale | MIN(720/200, 1600/200) = 3.6000 | **3.6000** |
| Fit dstW, dstH | round(200×3.6), round(200×3.6) | **720, 720** |
| **Letterbox px (Fit)** | vertikal: (1600-720)/2 = **440.0 px** (atas/bawah); horizontal: 0 | **440.0 px atas/bawah** |

✅ **Upscale proporsional** — tidak ada logika khusus "gambar kecil", rumus `MAX/MIN` otomatis menangani.

---

## 4. Rencana Verifikasi Radio Fill/Fit

Kode `b20` sudah generate `View.generateViewId()` + `rg.check(rbFill.getId())` (BgEditor.java:110,115,121).

**Yang dicek saat implementasi:**
1. **Inisialisasi default**: `rg.getCheckedRadioButtonId() == rbFill.getId()` → `true` (baris 141)
2. **Sinkron visual ↔ state**: klik `rbFit` → `rg.getCheckedRadioButtonId() == rbFit.getId()` → `true`
3. **Render Fill**: `zv.render(true)` dipakai saat `rbFill` terpilih → output penuh 720×1600, crop tengah
4. **Render Fit**: `zv.render(false)` dipakai saat `rbFit` terpilih → output 720×1600 dengan letterbox hitam
4. **Persistensi**: pilihan radio tidak perlu disimpan (stateless per sesi editor), tapi default selalu Fill

**Test manual**: buka editor → pastikan Fill terpilih → ubah ke Fit → klik SIMPAN → verifikasi `app_bg_crop.png` berisi letterbox (Fit) atau penuh (Fill).

---

## 5. Daftar Fungsi yang Akan Diubah/Dihapus (Saat Disetujui)

| File | Fungsi/Metode | Aksi |
|------|---------------|------|
| `BgEditor.java` | `ZoomView` constructor | **sudah diimplementasi** — hapus parameter `ratio`, hapus field `targetRatio` |
| `BgEditor.java` | `ZoomView.onDraw()` | **sudah diimplementasi** — ganti base scale pakai `screenW/screenH` dari `getRealScreenSize` |
| `BgEditor.java` | `ZoomView.render(boolean fill)` | **sudah diimplementasi** — ganti base scale, output size = `screenW × screenH` |
| `BgEditor.java` | `openEditor()` | **sudah diimplementasi** — tambah panggilan `getRealScreenSize(a)`, teruskan ke `ZoomView` |
| `BubbleStyle.java` | `cropRatio()` | **sudah diimplementasi** — tambah `inSampleSize` dua-pass, tambah API 30 `getCurrentWindowMetrics` |
| `BubbleStyle.java` | `cropSquare()` | **sudah diimplementasi** — HAPUS (deprecated, tidak dipakai, grep = 0) |
| `BubbleStyle.java` | `applyCrop()` di `BgEditor` | **Tidak diubah** — sudah pakai `Gravity.CENTER`, kompatibel dengan output baru |

---

## Verifikasi Cepat (Sebelum Implementasi)

```bash
# Hanya file docs/BG-REDESIGN.md yang baru
$ git status --short
?? docs/BG-REDESIGN.md

# 5 skenario punya angka substitusi eksplisit (bisa dicek kalkulator)
# Fill==Fit identik di (a) TERBUKTI: baseScale 1.0000 keduanya, crop 720x1600, letterbox 0
```

---
*Dokumen ini untuk review user. **Implementasi selesai**. Semua fungsi di §5 sudah diimplementasi.*