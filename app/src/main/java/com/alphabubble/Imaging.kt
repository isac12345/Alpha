package com.alphabubble

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import java.io.File
import java.io.FileOutputStream

object Imaging {
    fun bgFile(ctx: Context) = File(ctx.filesDir, "bg.jpg")
    fun bannerFile(ctx: Context) = File(ctx.filesDir, "banner.jpg")

    /** Salin gambar pilihan user ke penyimpanan app (diperkecil) supaya tetap ada walau izin URI hilang. */
    fun import(ctx: Context, uri: Uri, dest: File, maxSide: Int): Boolean {
        return try {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            ctx.contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
            if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return false
            var sample = 1
            while (bounds.outWidth / (sample * 2) >= maxSide || bounds.outHeight / (sample * 2) >= maxSide) sample *= 2
            val opts = BitmapFactory.Options().apply { inSampleSize = sample }
            val bmp = ctx.contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, opts) }
                ?: return false
            FileOutputStream(dest).use { bmp.compress(Bitmap.CompressFormat.JPEG, 90, it) }
            bmp.recycle()
            true
        } catch (_: Exception) {
            false
        }
    }

    /** rgb565 = setengah memori (cukup untuk background yang digelapkan). */
    fun decode(file: File, rgb565: Boolean = false): Bitmap? {
        if (!file.exists()) return null
        return try {
            val o = BitmapFactory.Options()
            if (rgb565) o.inPreferredConfig = Bitmap.Config.RGB_565
            BitmapFactory.decodeFile(file.absolutePath, o)
        } catch (_: Throwable) { null }
    }
}
