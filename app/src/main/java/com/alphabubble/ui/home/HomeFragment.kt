package com.alphabubble.ui.home

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.ImageView
import android.widget.TextView
import androidx.fragment.app.Fragment
import androidx.lifecycle.lifecycleScope
import com.alphabubble.NotifHelper
import com.alphabubble.Prefs
import com.alphabubble.R
import com.alphabubble.RootShell
import com.alphabubble.service.FloatingBubbleService
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.io.IOException

class HomeFragment : Fragment(R.layout.fragment_home) {

    private var tvProfileName: TextView? = null
    private var tvStatus: TextView? = null
    private var btnFloating: Button? = null
    private var segBattery: Button? = null
    private var segBalanced: Button? = null
    private var segPerf: Button? = null
    private var ivHomeBanner: ImageView? = null
    private var vHomeScrim: View? = null

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        tvProfileName = view.findViewById(R.id.tvProfileName)
        tvStatus = view.findViewById(R.id.tvStatus)
        btnFloating = view.findViewById(R.id.btnFloating)
        segBattery = view.findViewById(R.id.segBattery)
        segBalanced = view.findViewById(R.id.segBalanced)
        segPerf = view.findViewById(R.id.segPerformance)
        ivHomeBanner = view.findViewById(R.id.ivHomeBanner)
        vHomeScrim = view.findViewById(R.id.vHomeScrim)

        segBattery?.setOnClickListener { switchProfile("battery") }
        segBalanced?.setOnClickListener { switchProfile("balanced") }
        segPerf?.setOnClickListener { switchProfile("performance") }

        btnFloating?.setOnClickListener {
            val visible = Prefs.isFloatingVisible(requireContext())
            Prefs.setFloatingVisible(requireContext(), !visible)
            if (visible) {
                requireActivity().startService(FloatingBubbleService.getToggleIntent(requireContext()))
            } else {
                requireActivity().startService(FloatingBubbleService.getShowIntent(requireContext()))
            }
            refreshFloatingButton()
        }

        refreshProfile()
        refreshStatus()
        refreshFloatingButton()
        loadHomeBanner()
    }

    override fun onResume() {
        super.onResume()
        refreshProfile()
        refreshStatus()
        refreshFloatingButton()
        loadHomeBanner()
    }

    private fun refreshProfile() {
        lifecycleScope.launch {
            val profile = RootShell.readCurrentState() ?: "balanced"
            requireActivity().runOnUiThread {
                tvProfileName?.text = NotifHelper.labelFor(profile).uppercase()
                updateSegments(profile)
            }
        }
    }

    private fun refreshStatus() {
        lifecycleScope.launch {
            val hasRoot = RootShell.hasRoot()
            val modulePath = RootShell.findModulePath(requireContext())
            requireActivity().runOnUiThread {
                val rootStr = if (hasRoot) "Root: OK" else "Root: NO"
                val modStr = if (modulePath != null) "Module: $modulePath" else "Module: NOT FOUND"
                tvStatus?.text = "$rootStr | $modStr"
            }
        }
    }

    private fun refreshFloatingButton() {
        val visible = Prefs.isFloatingVisible(requireContext())
        btnFloating?.text = if (visible) "Sembunyikan Floating" else "Tampilkan Floating"
    }

    private fun switchProfile(profile: String) {
        lifecycleScope.launch {
            val result = RootShell.applyProfile(requireContext(), profile)
            if (result.success) {
                refreshProfile()
            }
        }
    }

    private fun updateSegments(active: String) {
        val segments = listOf(segBattery, segBalanced, segPerf)
        segments.forEachIndexed { i, btn ->
            btn?.let {
                val profile = listOf("battery", "balanced", "performance")[i]
                val isActive = profile == active
                it.setBackgroundResource(if (isActive) R.drawable.pill_solid else R.color.alpha_transparent)
                it.setTextColor(if (isActive) requireContext().getColor(R.color.alpha_dark) else requireContext().getColor(R.color.alpha_ink_dim))
                it.setTypeface(null, if (isActive) android.graphics.Typeface.BOLD else android.graphics.Typeface.NORMAL)
            }
        }
    }

    private fun loadHomeBanner() {
        lifecycleScope.launch {
            val bitmap = withContext(Dispatchers.IO) {
                loadBitmapFromPrefs()
            }
            requireActivity().runOnUiThread {
                if (bitmap != null) {
                    ivHomeBanner?.setImageBitmap(bitmap)
                    val mode = Prefs.bgMode(requireContext())
                    ivHomeBanner?.scaleType = if (mode == "fill") ImageView.ScaleType.CENTER_CROP else ImageView.ScaleType.FIT_CENTER
                    val alpha = Prefs.bgAlpha(requireContext())
                    ivHomeBanner?.setImageAlpha((alpha * 255 / 100).coerceIn(0, 255))
                } else {
                    ivHomeBanner?.setImageResource(R.drawable.banner)
                    ivHomeBanner?.scaleType = ImageView.ScaleType.CENTER_CROP
                    ivHomeBanner?.setImageAlpha(255)
                }
            }
        }
    }

    private suspend fun loadBitmapFromPrefs(): Bitmap? = withContext(Dispatchers.IO) {
        val path = Prefs.bgImagePath(requireContext())
        if (path == null) return@withContext null

        val file = File(path)
        if (!file.exists()) {
            Prefs.setBgImagePath(requireContext(), null)
            return@withContext null
        }

        val options = BitmapFactory.Options().apply {
            inJustDecodeBounds = true
        }
        BitmapFactory.decodeFile(path, options)

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
}