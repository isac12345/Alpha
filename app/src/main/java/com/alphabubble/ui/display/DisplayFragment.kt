package com.alphabubble.ui.display

import android.app.Activity
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.net.Uri
import android.os.Bundle
import android.provider.MediaStore
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.ImageView
import android.widget.SeekBar
import android.widget.TextView
import androidx.activity.result.contract.ActivityResultContracts
import androidx.fragment.app.Fragment
import androidx.lifecycle.lifecycleScope
import com.alphabubble.DexoptDialog
import com.alphabubble.Prefs
import com.alphabubble.R
import com.alphabubble.RootShell
import com.alphabubble.service.FloatingBubbleService
import com.alphabubble.service.ProfileMonitorService
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.io.InputStream

class DisplayFragment : Fragment(R.layout.fragment_display) {

    // Background UI
    private var ivBgPreview: ImageView? = null
    private var vBgScrim: View? = null
    private var btnPickBg: Button? = null
    private var btnDefaultBg: Button? = null
    private var btnModeFill: Button? = null
    private var btnModeFit: Button? = null
    private var seekBgAlpha: SeekBar? = null
    private var tvBgAlphaLabel: TextView? = null

    // Resolution UI
    private var tvResolutionPreview: TextView? = null
    private var tvResolutionActive: TextView? = null
    private var resButtons: List<Button> = emptyList()
    private var btnApplyRes: Button? = null
    private var btnResetRes: Button? = null

    // Floating UI
    private var seekFloatingSize: SeekBar? = null
    private var tvFloatingSizeLabel: TextView? = null
    private var btnFloatingShow: Button? = null

    // Tools UI
    private var btnDexopt: Button? = null
    private var swAutostart: androidx.appcompat.widget.SwitchCompat? = null
    private var swNotifEnabled: androidx.appcompat.widget.SwitchCompat? = null

    private val ctx by lazy { requireContext() }
    private val prefs = Prefs

    private var currentBgMode = "fill" // "fill" or "fit"
    private var selectedPercent = 100

    private val pickImage = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
        if (result.resultCode == Activity.RESULT_OK) {
            result.data?.data?.let { uri ->
                copyImageToInternal(uri)
            }
        }
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        // Background views
        ivBgPreview = view.findViewById(R.id.ivBgPreview)
        vBgScrim = view.findViewById(R.id.vBgScrim)
        btnPickBg = view.findViewById(R.id.btnPickBackground)
        btnDefaultBg = view.findViewById(R.id.btnDefaultBackground)
        btnModeFill = view.findViewById(R.id.btnModeFill)
        btnModeFit = view.findViewById(R.id.btnModeFit)
        seekBgAlpha = view.findViewById(R.id.seekBackgroundAlpha)
        tvBgAlphaLabel = view.findViewById(R.id.tvBgAlphaLabel)

        // Resolution views
        tvResolutionPreview = view.findViewById(R.id.tvResolutionPreview)
        tvResolutionActive = view.findViewById(R.id.tvResolutionActive)
        btnApplyRes = view.findViewById(R.id.btnApplyResolution)
        btnResetRes = view.findViewById(R.id.btnResetResolution)

        // Tools views
        btnDexopt = view.findViewById(R.id.btnDexopt)
        swAutostart = view.findViewById(R.id.swAutostart)

        resButtons = listOf(
            view.findViewById(R.id.res60),
            view.findViewById(R.id.res70),
            view.findViewById(R.id.res80),
            view.findViewById(R.id.res90),
            view.findViewById(R.id.res100)
        )

        // Load saved preferences
        currentBgMode = prefs.bgMode(ctx)
        updateBgModeUI()

        // Background alpha
        seekBgAlpha?.progress = prefs.bgAlpha(ctx)
        updateAlphaLabel(prefs.bgAlpha(ctx))
        seekBgAlpha?.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(seekBar: SeekBar, progress: Int, fromUser: Boolean) {
                if (fromUser) {
                    prefs.setBgAlpha(ctx, progress)
                    updateAlphaLabel(progress)
                    applyBgAlphaToPreview(progress)
                }
            }
            override fun onStartTrackingTouch(seekBar: SeekBar) {}
            override fun onStopTrackingTouch(seekBar: SeekBar) {}
        })

        // Pick image
        btnPickBg?.setOnClickListener {
            val intent = Intent(Intent.ACTION_PICK, MediaStore.Images.Media.EXTERNAL_CONTENT_URI)
            pickImage.launch(intent)
        }

        // Default banner
        btnDefaultBg?.setOnClickListener {
            prefs.setBgImagePath(ctx, null)
            prefs.setBgMode(ctx, "fill")
            currentBgMode = "fill"
            updateBgModeUI()
            loadBgPreview()
        }

        // Mode buttons
        btnModeFill?.setOnClickListener { setBgMode("fill") }
        btnModeFit?.setOnClickListener { setBgMode("fit") }

        // Resolution buttons
        resButtons.forEachIndexed { i, btn ->
            val percent = (i + 1) * 10 + 50 // 60, 70, 80, 90, 100
            btn.text = "${percent}%"
            btn.setOnClickListener {
                selectedPercent = percent
                updateResButtonsUI()
            }
        }

        btnApplyRes?.setOnClickListener { applyResolution(selectedPercent) }
        btnResetRes?.setOnClickListener { resetResolution() }
        btnDexopt?.setOnClickListener { DexoptDialog().show(childFragmentManager, "dexopt") }

        swAutostart?.isChecked = prefs.isAutostart(ctx)
        swAutostart?.setOnCheckedChangeListener { _, checked ->
            prefs.setAutostart(ctx, checked)
        }

        // Notification toggle
        swNotifEnabled = view.findViewById(R.id.swNotifEnabled)
        swNotifEnabled?.isChecked = prefs.isNotifEnabled(ctx)
        swNotifEnabled?.setOnCheckedChangeListener { _, checked ->
            prefs.setNotifEnabled(ctx, checked)
            // Restart profile monitor service to pick up the change
            if (checked) {
                requireContext().startForegroundService(Intent(requireContext(), ProfileMonitorService::class.java))
            } else {
                requireContext().stopService(Intent(requireContext(), ProfileMonitorService::class.java))
            }
        }

        // Floating views
        seekFloatingSize = view.findViewById(R.id.seekFloatingSize)
        tvFloatingSizeLabel = view.findViewById(R.id.tvFloatingSizeLabel)
        btnFloatingShow = view.findViewById(R.id.btnFloatingShow)

        // Floating size slider (60-150% -> progress 0-90)
        val savedScale = prefs.floatingSize(ctx)
        seekFloatingSize?.progress = ((savedScale - 0.6f) / 0.9f * 90).toInt().coerceIn(0, 90)
        updateFloatingSizeLabel(savedScale)
        seekFloatingSize?.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(seekBar: SeekBar, progress: Int, fromUser: Boolean) {
                if (fromUser) {
                    val scale = 0.6f + (progress / 90f) * 0.9f
                    prefs.setFloatingSize(ctx, scale)
                    updateFloatingSizeLabel(scale)
                    applyFloatingSizeLive(scale)
                }
            }
            override fun onStartTrackingTouch(seekBar: SeekBar) {}
            override fun onStopTrackingTouch(seekBar: SeekBar) {}
        })

        btnFloatingShow?.setOnClickListener {
            requireActivity().startService(FloatingBubbleService.getShowIntent(requireContext()))
        }

        // Initial loads
        loadBgPreview()
        loadResolution()
    }

    private fun setBgMode(mode: String) {
        currentBgMode = mode
        prefs.setBgMode(ctx, mode)
        updateBgModeUI()
        loadBgPreview()
    }

    private fun updateBgModeUI() {
        val isFill = currentBgMode == "fill"
        btnModeFill?.setBackgroundResource(if (isFill) R.drawable.pill_solid else R.color.alpha_transparent)
        btnModeFill?.setTextColor(if (isFill) requireContext().getColor(R.color.alpha_dark) else requireContext().getColor(R.color.alpha_ink_dim))
        btnModeFit?.setBackgroundResource(if (!isFill) R.drawable.pill_solid else R.color.alpha_transparent)
        btnModeFit?.setTextColor(if (!isFill) requireContext().getColor(R.color.alpha_dark) else requireContext().getColor(R.color.alpha_ink_dim))
    }

    private fun updateResButtonsUI() {
        resButtons.forEachIndexed { i, btn ->
            val percent = (i + 1) * 10 + 50
            val isSelected = percent == selectedPercent
            btn.setBackgroundResource(if (isSelected) R.drawable.pill_solid else R.color.alpha_transparent)
            btn.setTextColor(if (isSelected) requireContext().getColor(R.color.alpha_dark) else requireContext().getColor(R.color.alpha_ink_dim))
        }
    }

    private fun loadBgPreview() {
        lifecycleScope.launch {
            val bitmap = withContext(Dispatchers.IO) {
                loadBitmapFromPrefs()
            }
            requireActivity().runOnUiThread {
                if (bitmap != null) {
                    ivBgPreview?.setImageBitmap(bitmap)
                    ivBgPreview?.scaleType = if (currentBgMode == "fill") ImageView.ScaleType.CENTER_CROP else ImageView.ScaleType.FIT_CENTER
                } else {
                    ivBgPreview?.setImageResource(R.drawable.banner)
                    ivBgPreview?.scaleType = if (currentBgMode == "fill") ImageView.ScaleType.CENTER_CROP else ImageView.ScaleType.FIT_CENTER
                }
                applyBgAlphaToPreview(prefs.bgAlpha(ctx))
            }
        }
    }

    private suspend fun loadBitmapFromPrefs(): Bitmap? = withContext(Dispatchers.IO) {
        val path = prefs.bgImagePath(ctx)
        if (path == null) return@withContext null

        val file = File(path)
        if (!file.exists()) {
            prefs.setBgImagePath(ctx, null)
            return@withContext null
        }

        // Decode with downsampling to save memory
        val options = BitmapFactory.Options().apply {
            inJustDecodeBounds = true
        }
        BitmapFactory.decodeFile(path, options)

        // Target max dimension ~1080px
        val targetSize = 1080
        var inSampleSize = 1
        if (options.outHeight > targetSize || options.outWidth > targetSize) {
            val halfH = options.outHeight / 2
            val halfW = options.outWidth / 2
            while ((halfH / inSampleSize) >= targetSize && (halfW / inSampleSize) >= targetSize) {
                inSampleSize *= 2
            }
        }
        options.inSampleSize = inSampleSize
        options.inJustDecodeBounds = false
        options.inPreferredConfig = Bitmap.Config.ARGB_8888

        var bitmap = BitmapFactory.decodeFile(path, options)
        if (bitmap == null) return@withContext null

        // Apply EXIF rotation
        bitmap = rotateBitmapIfNeeded(bitmap, path)
        bitmap
    }

    private fun rotateBitmapIfNeeded(bitmap: Bitmap, path: String): Bitmap {
        return try {
            val exif = ExifInterface(path)
            val orientation = exif.getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
            val matrix = Matrix()
            when (orientation) {
                ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
                ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
                ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(270f)
                ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.postScale(-1f, 1f)
                ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.postScale(1f, -1f)
                else -> return bitmap
            }
            Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
        } catch (e: IOException) {
            bitmap
        }
    }

    private fun applyBgAlphaToPreview(alpha: Int) {
        val alpha255 = (alpha * 255 / 100).coerceIn(0, 255)
        ivBgPreview?.setImageAlpha(alpha255)
        updateAlphaLabel(alpha)
    }

    private fun updateAlphaLabel(alpha: Int) {
        tvBgAlphaLabel?.text = "Transparansi background: ${alpha}%"
    }

    private fun copyImageToInternal(uri: Uri) {
        lifecycleScope.launch {
            try {
                val input = requireContext().contentResolver.openInputStream(uri) ?: return@launch
                val dest = File(requireContext().filesDir, "custom_bg.jpg")
                FileOutputStream(dest).use { output ->
                    input.copyTo(output)
                }
                prefs.setBgImagePath(ctx, dest.absolutePath)
                prefs.setBgMode(ctx, "fill")
                currentBgMode = "fill"
                updateBgModeUI()
                loadBgPreview()
            } catch (e: Exception) {
                // ignore
            }
        }
    }

    private fun loadResolution() {
        lifecycleScope.launch {
            val info = RootShell.activeDisplayInfo()
            requireActivity().runOnUiThread {
                if (info != null) {
                    tvResolutionPreview?.text = "Resolusi: ${info.width}x${info.height} @ ${info.refreshRates.maxOrNull() ?: 60}Hz"
                    tvResolutionActive?.text = "Resolusi aktif saat ini: ${info.width}x${info.height}"
                } else {
                    tvResolutionPreview?.text = "Resolusi: membaca..."
                    tvResolutionActive?.text = "Resolusi aktif saat ini: —"
                }
            }
        }
    }

    private fun applyResolution(percent: Int) {
        lifecycleScope.launch {
            val info = RootShell.activeDisplayInfo()
            info?.let {
                val result = RootShell.applyDisplay(it, percent)
                if (result.success) loadResolution()
            }
        }
    }

    private fun resetResolution() {
        lifecycleScope.launch {
            val result = RootShell.resetDisplay()
            if (result.success) loadResolution()
        }
    }

    private fun updateFloatingSizeLabel(scale: Float) {
        tvFloatingSizeLabel?.text = "Ukuran: ${(scale * 100).toInt()}%"
    }

    private fun applyFloatingSizeLive(scale: Float) {
        // Send broadcast or use shared prefs - the service reads prefs on next create
        // For live update, we could restart the service or use a broadcast
        // Simple approach: update prefs, service will pick up on next start
        // For true live update, we'd need to communicate with running service
        prefs.setFloatingSize(ctx, scale)
    }
}