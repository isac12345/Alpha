package com.alphabubble.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.Point
import android.graphics.PorterDuff
import android.graphics.drawable.Icon
import android.media.ExifInterface
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.view.animation.AccelerateDecelerateInterpolator
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.app.NotificationCompat
import com.alphabubble.NotifHelper
import com.alphabubble.Prefs
import com.alphabubble.R
import com.alphabubble.RootShell
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.io.IOException
import kotlin.math.abs
import androidx.core.animation.doOnEnd

class FloatingBubbleService : Service() {

    companion object {
        const val ACTION_TOGGLE = "com.alphabubble.FLOATING_TOGGLE"
        const val ACTION_SHOW = "com.alphabubble.FLOATING_SHOW"
        const val CHANNEL_ID = "alpha_floating"
        const val NOTIF_ID = 21
        const val PREFS_NAME = "alpha_bubble"
        private val PROFILES = listOf("battery", "balanced", "performance")
        private val SHORT = mapOf("battery" to "BAT", "balanced" to "BAL", "performance" to "PERF")
        private val PROFILE_COLORS = mapOf(
            "battery" to 0xFF4CAF50.toInt(),   // Green
            "balanced" to 0xFF2196F3.toInt(),  // Blue
            "performance" to 0xFFFF5722.toInt() // Orange
        )

        @JvmStatic
        fun getToggleIntent(ctx: Context): Intent {
            return Intent(ctx, FloatingBubbleService::class.java).setAction(ACTION_TOGGLE)
        }

        @JvmStatic
        fun getShowIntent(ctx: Context): Intent {
            return Intent(ctx, FloatingBubbleService::class.java).setAction(ACTION_SHOW)
        }
    }

    private var wm: WindowManager? = null
    private var root: FrameLayout? = null
    private var bg: ImageView? = null
    private var collapsedView: View? = null
    private var expandedView: View? = null
    private var params: WindowManager.LayoutParams? = null
    private var activeProfile = "balanced"
    private var hidden = false
    private val ui = Handler(Looper.getMainLooper())
    private var refresher: Runnable? = null
    private var bgBmp: Bitmap? = null
    private var lastTouchTime = 0L
    private var lastKnownScale = 1.0f
    private var touchStartX = 0f
    private var touchStartY = 0f
    private var startParamsX = 0
    private var startParamsY = 0
    private var isExpanded = false
    private var expandJob: Job? = null
    private var idleJob: Job? = null
    private var collapseJob: Job? = null
    private val scope = CoroutineScope(Dispatchers.Main)
    private var currentScale = 1.0f
    private var savedX = 0
    private var savedY = 0

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        startForeground(NOTIF_ID, buildNotification())
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_TOGGLE -> {
                val prefs = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
                val currentlyHidden = prefs.getBoolean("hidden", false)
                prefs.edit().putBoolean("hidden", !currentlyHidden).apply()
                hidden = !currentlyHidden
                applyVisibility()
            }
            ACTION_SHOW -> {
                val prefs = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
                prefs.edit().putBoolean("hidden", false).apply()
                hidden = false
                if (root == null) attach()
                applyVisibility()
            }
            else -> {
                if (!checkOverlayPermission()) {
                    stopSelf()
                    return START_NOT_STICKY
                }
                if (root == null) attach()
                scheduleRefresh()
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        refresher?.let { ui.removeCallbacks(it) }
        expandJob?.cancel()
        idleJob?.cancel()
        collapseJob?.cancel()
        try {
            root?.let { wm?.removeView(it) }
        } catch (e: Exception) {
            // ignore
        }
        root = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun checkOverlayPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            android.provider.Settings.canDrawOverlays(this)
        } else true
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(CHANNEL_ID, "Alpha Floating", NotificationManager.IMPORTANCE_LOW)
            channel.description = "Floating profile switcher"
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val showIntent = Intent(this, FloatingBubbleService::class.java).setAction(ACTION_SHOW)
        val toggleIntent = Intent(this, FloatingBubbleService::class.java).setAction(ACTION_TOGGLE)
        val showPending = PendingIntent.getService(this, 0, showIntent, PendingIntent.FLAG_IMMUTABLE)
        val togglePending = PendingIntent.getService(this, 1, toggleIntent, PendingIntent.FLAG_IMMUTABLE)
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification_small)
            .setContentTitle("Alpha Floating")
            .setContentText("Tap untuk tampilkan / sembunyikan")
            .setContentIntent(showPending)
            .addAction(R.drawable.ic_notification_small, "Tampilkan", showPending)
            .addAction(R.drawable.ic_notification_small, "Sembunyikan", togglePending)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    private fun attach() {
        wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        currentScale = Prefs.floatingSize(this)

        root = FrameLayout(this)
        root?.setOnTouchListener(onTouchListener)

        // Background
        bg = ImageView(this)
        bg?.scaleType = ImageView.ScaleType.CENTER_CROP
        root?.addView(bg, FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT
        ))

        // Collapsed View (Circle)
        createCollapsedView()
        root?.addView(collapsedView!!, FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
            Gravity.TOP or Gravity.START
        ))

        // Expanded View (Pill)
        createExpandedView()
        root?.addView(expandedView!!, FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
            Gravity.CENTER
        ))

        // Window params
        val baseSize = (44f * currentScale).toInt()
        params = WindowManager.LayoutParams(
            baseSize,
            baseSize,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else WindowManager.LayoutParams.TYPE_PHONE,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                or WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL
                or WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH
                or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
        }

        // Restore saved position
        val prefs = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
        savedX = prefs.getInt("float_x", 0)
        savedY = prefs.getInt("float_y", 100)
        if (savedX == 0 && savedY == 100) {
            // First run - position at right edge, middle vertically
            val display = wm?.defaultDisplay
            val point = Point()
            display?.getRealSize(point)
            savedX = point.x - baseSize
            savedY = (point.y - baseSize) / 2
        }
        params?.x = savedX
        params?.y = savedY

        wm?.addView(root, params)
        applyLook()
        applyVisibility()
        scheduleIdleDim()
    }

    private fun createCollapsedView() {
        collapsedView = FrameLayout(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        }

        val baseSize = (44f * currentScale).toInt()
        val circle = CircleView(this).apply {
            layoutParams = FrameLayout.LayoutParams(baseSize, baseSize)
        }
        (collapsedView as? FrameLayout)?.addView(circle)
    }

    private fun createExpandedView() {
        expandedView = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.CENTER
            )
            visibility = View.GONE
            setPadding(24, 12, 24, 12)
        }

        val pillBg = View(this).apply {
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
            background = createPillBackground()
        }
        // We'll use a FrameLayout to overlay the pill background
        val pillContainer = FrameLayout(this).apply {
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        }
        pillContainer.addView(pillBg)

        val content = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        }

        for (i in 0..2) {
            val profile = PROFILES[i]
            val tv = TextView(this).apply {
                text = NotifHelper.labelFor(profile)
                textSize = 14f
                typeface = android.graphics.Typeface.create("sans-serif-medium", android.graphics.Typeface.NORMAL)
                setPadding(32, 16, 32, 16)
                setOnClickListener { selectProfile(profile) }
                tag = profile
            }
            content.addView(tv)
            // Store reference for updates
            when (profile) {
                "battery" -> expandedView?.tag = tv
                "balanced" -> expandedView?.tag = tv // We'll use findViewWithTag later
            }
        }

        pillContainer.addView(content)
        (expandedView as? ViewGroup)?.addView(pillContainer)
    }

    private fun createPillBackground(): android.graphics.drawable.GradientDrawable {
        return android.graphics.drawable.GradientDrawable().apply {
            setColor(0xFF1E1E1E.toInt()) // alpha_dark3
            cornerRadius = 1000f
            setStroke(2, 0x33FFFFFF.toInt()) // Thin white stroke
        }
    }

    private inner class CircleView(context: Context) : View(context) {
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = 2f
            color = 0x33FFFFFF.toInt()
        }
        private val dotPaint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            textAlign = Paint.Align.CENTER
            typeface = android.graphics.Typeface.create("sans-serif-medium", android.graphics.Typeface.NORMAL)
        }

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            val centerX = width / 2f
            val centerY = height / 2f
            val radius = (width / 2f) - 1f

            // Background circle
            paint.color = 0xCC1E1E1E.toInt() // Semi-transparent dark
            canvas.drawCircle(centerX, centerY, radius, paint)

            // Stroke
            canvas.drawCircle(centerX, centerY, radius, strokePaint)

            // Profile indicator dot (top-right)
            val dotColor = PROFILE_COLORS[activeProfile] ?: 0xFFFFFFFF.toInt()
            dotPaint.color = dotColor
            val dotRadius = width * 0.18f
            val dotX = centerX + radius * 0.5f
            val dotY = centerY - radius * 0.5f
            canvas.drawCircle(dotX, dotY, dotRadius, dotPaint)

            // Profile letter
            val letter = SHORT[activeProfile] ?: "?"
            textPaint.color = 0xFFFFFFFF.toInt()
            textPaint.textSize = width * 0.35f
            val bounds = android.graphics.Rect()
            textPaint.getTextBounds(letter, 0, letter.length, bounds)
            canvas.drawText(letter, centerX, centerY + bounds.height() / 2f, textPaint)
        }
    }

    private val onTouchListener = View.OnTouchListener { v, event ->
        when (event.action) {
            MotionEvent.ACTION_DOWN -> {
                touchStartX = event.rawX
                touchStartY = event.rawY
                startParamsX = params?.x ?: 0
                startParamsY = params?.y ?: 0
                lastTouchTime = System.currentTimeMillis()
                expandJob?.cancel()
                idleJob?.cancel()
                collapseJob?.cancel()
                if (!isExpanded) expand()
                true
            }
            MotionEvent.ACTION_MOVE -> {
                val dx = event.rawX - touchStartX
                val dy = event.rawY - touchStartY
                // If moved significantly, treat as drag
                if (abs(dx) > 10 || abs(dy) > 10) {
                    params?.x = (startParamsX + dx).toInt()
                    params?.y = (startParamsY + dy).toInt()
                    clampToScreen()
                    root?.let { wm?.updateViewLayout(it, params!!) }
                    idleJob?.cancel()
                }
                true
            }
            MotionEvent.ACTION_UP -> {
                val duration = System.currentTimeMillis() - lastTouchTime
                if (duration > 800) {
                    // Long press - hide completely
                    hapticFeedback()
                    hidden = true
                    getSharedPreferences(PREFS_NAME, MODE_PRIVATE).edit().putBoolean("hidden", true).apply()
                    applyVisibility()
                } else if (!isExpanded) {
                    // Quick tap on collapsed - expand
                    expand()
                } else if (isExpanded && !isTouchOnExpanded(event)) {
                    // Tap outside expanded - collapse
                    collapse()
                }
                snapToEdgeWithAnimation()
                scheduleIdleDim()
                true
            }
        }
        false
    }

    private fun isTouchOnExpanded(event: MotionEvent): Boolean {
        val loc = intArrayOf(0, 0)
        (expandedView as? View)?.getLocationOnScreen(loc)
        return event.rawX >= loc[0] && event.rawX <= loc[0] + expandedView?.width!! &&
               event.rawY >= loc[1] && event.rawY <= loc[1] + expandedView!!.height!!
    }

    private fun expand() {
        isExpanded = true
        idleJob?.cancel()
        collapseJob?.cancel()

        collapsedView?.animate()
            ?.alpha(0f)
            ?.scaleX(0.8f)
            ?.scaleY(0.8f)
            ?.setDuration(150)
            ?.setInterpolator(AccelerateDecelerateInterpolator())
            ?.start()

        expandedView?.visibility = View.VISIBLE
        expandedView?.alpha = 0f
        expandedView?.scaleX = 0.8f
        expandedView?.scaleY = 0.8f
        expandedView?.animate()
            ?.alpha(1f)
            ?.scaleX(1f)
            ?.scaleY(1f)
            ?.setDuration(200)
            ?.setInterpolator(AccelerateDecelerateInterpolator())
            ?.start()

        // Update params for expanded
        val expandedSize = (120f * currentScale).toInt() // wider for pill
        params?.width = ViewGroup.LayoutParams.WRAP_CONTENT
        params?.height = ViewGroup.LayoutParams.WRAP_CONTENT
        params?.gravity = Gravity.CENTER
        root?.let { wm?.updateViewLayout(it, params!!) }

        // Auto-collapse after 4s
        collapseJob = scope.launch {
            delay(4000)
            if (isExpanded) collapse()
        }
    }

    private fun collapse() {
        isExpanded = false
        expandJob?.cancel()
        collapseJob?.cancel()

        expandedView?.animate()
            ?.alpha(0f)
            ?.scaleX(0.8f)
            ?.scaleY(0.8f)
            ?.setDuration(150)
            ?.setInterpolator(AccelerateDecelerateInterpolator())
            ?.withEndAction { expandedView?.visibility = View.GONE }
            ?.start()

        collapsedView?.animate()
            ?.alpha(1f)
            ?.scaleX(1f)
            ?.scaleY(1f)
            ?.setDuration(200)
            ?.setInterpolator(AccelerateDecelerateInterpolator())
            ?.start()

        val baseSize = (44f * currentScale).toInt()
        params?.width = baseSize
        params?.height = baseSize
        params?.gravity = Gravity.TOP or Gravity.START
        root?.let { wm?.updateViewLayout(it, params!!) }

        scheduleIdleDim()
    }

    private fun snapToEdgeWithAnimation() {
        val display = wm?.defaultDisplay ?: return
        val point = Point()
        display.getRealSize(point)
        val screenW = point.x
        val screenH = point.y

        val x = params?.x ?: 0
        val y = params?.y ?: 0
        val w = params?.width ?: (44f * currentScale).toInt()
        val h = params?.height ?: (44f * currentScale).toInt()

        val newX = if (x < screenW / 2) 0 else screenW - w
        val newY = y.coerceIn(0, screenH - h)

        if (newX != x || newY != y) {
            // Animate to edge
            val startX = x
            val startY = y
            val anim = android.animation.ValueAnimator.ofFloat(0f, 1f).apply {
                duration = 300
                interpolator = AccelerateDecelerateInterpolator()
                addUpdateListener { animation ->
                    val fraction = animation.animatedValue as Float
                    params?.x = (startX + (newX - startX) * fraction).toInt()
                    params?.y = (startY + (newY - startY) * fraction).toInt()
                    root?.let { wm?.updateViewLayout(it, params!!) }
                }
                doOnEnd {
                    savePosition()
                }
            }
            anim.start()
        } else {
            savePosition()
        }
    }

    private fun savePosition() {
        val prefs = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
        prefs.edit()
            .putInt("float_x", params?.x ?: 0)
            .putInt("float_y", params?.y ?: 0)
            .apply()
    }

    private fun clampToScreen() {
        val display = wm?.defaultDisplay ?: return
        val point = Point()
        display.getRealSize(point)
        val screenW = point.x
        val screenH = point.y
        val w = params?.width ?: (44f * currentScale).toInt()
        val h = params?.height ?: (44f * currentScale).toInt()
        params?.x = params?.x?.coerceIn(0, screenW - w) ?: 0
        params?.y = params?.y?.coerceIn(0, screenH - h) ?: 0
    }

    private fun applyLook() {
        val prefs = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
        val alpha = prefs.getInt("bg_alpha", 255)
        val mode = prefs.getString("bg_mode", "fill") ?: "fill"

        val bgPath = prefs.getString("bg_image_path", null)
        if (bgPath != null) {
            val file = File(bgPath)
            if (file.exists()) {
                val options = BitmapFactory.Options().apply {
                    inJustDecodeBounds = true
                }
                BitmapFactory.decodeFile(bgPath, options)

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

                var bitmap = BitmapFactory.decodeFile(bgPath, options)
                if (bitmap != null) {
                    bitmap = rotateBitmapIfNeeded(bitmap, bgPath)
                    bgBmp = bitmap
                } else {
                    bgBmp = null
                }
            } else {
                bgBmp = null
            }
        } else {
            bgBmp = null
        }

        bg?.setImageBitmap(bgBmp)
        if (bgBmp == null) {
            bg?.setImageResource(R.drawable.banner)
        }
        bg?.scaleType = if (mode == "fill") ImageView.ScaleType.CENTER_CROP else ImageView.ScaleType.FIT_CENTER
        bg?.setImageAlpha(alpha)

        updateExpandedView()
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

    private fun updateExpandedView() {
        expandedView?.let { container ->
            val frame = (container as? ViewGroup)?.getChildAt(0) as? FrameLayout
            val content = frame?.getChildAt(1) as? LinearLayout
            if (content != null) {
                for (i in 0..2) {
                    val tv = content.getChildAt(i) as? TextView
                    val profile = PROFILES[i]
                    val isActive = profile == activeProfile
                    tv?.apply {
                        setTextColor((if (isActive) 0xFFFFFFFF.toInt() else 0x88FFFFFF.toInt()))
                        setTypeface(null, if (isActive) android.graphics.Typeface.BOLD else android.graphics.Typeface.NORMAL)
                        // Update background per segment
                        val pillBg = (parent as? FrameLayout)?.getChildAt(0) as? View
                        // We'll handle active segment highlight via the FrameLayout children
                    }
                }
                // Highlight active segment
                val pillContainer = (container as? ViewGroup)?.getChildAt(0) as? FrameLayout
                if (pillContainer != null) {
                    // Add highlight overlay for active segment
                    highlightActiveSegment(pillContainer, content, activeProfile)
                }
            }
        }
    }

    private fun highlightActiveSegment(pillContainer: FrameLayout, content: LinearLayout, profile: String) {
        val index = PROFILES.indexOf(profile)
        if (index < 0 || index >= content.childCount) return

        val activeView = content.getChildAt(index)
        val highlight = android.graphics.drawable.GradientDrawable().apply {
            setColor(0xFFFFFFFF.toInt()) // White for active
            cornerRadius = 1000f
        }
        activeView.background = highlight
        (activeView as? TextView)?.setTextColor(0xFF000000.toInt())

        // Reset others
        for (i in 0..2) {
            if (i != index) {
                val other = content.getChildAt(i) as? TextView
                other?.setBackgroundColor(Color.TRANSPARENT)
                other?.setTextColor(0xFFFFFFFF.toInt())
            }
        }
    }

    private fun selectProfile(profile: String) {
        hapticFeedback()
        scope.launch {
            val result = RootShell.applyProfile(this@FloatingBubbleService, profile)
            if (result.success) {
                activeProfile = profile
                ui.post { updateExpandedView() }
                // Also update collapsed view dot
                collapsedView?.invalidate()
            }
        }
        collapse()
    }

    private fun applyVisibility() {
        root?.visibility = if (hidden) View.GONE else View.VISIBLE
    }

    private fun scheduleIdleDim() {
        idleJob?.cancel()
        idleJob = scope.launch {
            delay(3000)
            if (!isExpanded && !hidden) {
                collapsedView?.animate()
                    ?.alpha(0.4f)
                    ?.setDuration(500)
                    ?.start()
                // Snap half to edge
                snapHalfToEdge()
            }
        }
    }

    private fun snapHalfToEdge() {
        val display = wm?.defaultDisplay ?: return
        val point = Point()
        display.getRealSize(point)
        val screenW = point.x
        val screenH = point.y
        val w = params?.width ?: (44f * currentScale).toInt()
        val h = params?.height ?: (44f * currentScale).toInt()
        val x = params?.x ?: 0
        val y = params?.y ?: 0

        val targetX = if (x < screenW / 2) -w / 2 else screenW - w / 2
        val targetY = y.coerceIn(0, screenH - h)

        val anim = android.animation.ValueAnimator.ofFloat(0f, 1f).apply {
            duration = 500
            interpolator = AccelerateDecelerateInterpolator()
            addUpdateListener { animation ->
                val fraction = animation.animatedValue as Float
                params?.x = (x + (targetX - x) * fraction).toInt()
                params?.y = (y + (targetY - y) * fraction).toInt()
                root?.let { wm?.updateViewLayout(it, params!!) }
            }
        }
        anim.start()
    }

    private fun hapticFeedback() {
        val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator?.vibrate(VibrationEffect.createOneShot(30, VibrationEffect.DEFAULT_AMPLITUDE))
        } else {
            vibrator?.vibrate(30)
        }
    }

    private fun scheduleRefresh() {
        refresher = object : Runnable {
            override fun run() {
                refreshProfile()
                checkAndApplyFloatingSize()
                ui.postDelayed(this, 5000)
            }
        }
        ui.post(refresher!!)
    }

    private fun checkAndApplyFloatingSize() {
        val prefs = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
        val newScale = prefs.getFloat("floating_size", 1.0f)
        if (abs(newScale - lastKnownScale) > 0.01f) {
            lastKnownScale = newScale
            applyFloatingSizeLive(newScale)
        }
    }

    private fun applyFloatingSizeLive(scale: Float) {
        currentScale = scale
        val baseSize = (44f * currentScale).toInt()
        if (!isExpanded) {
            params?.width = baseSize
            params?.height = baseSize
            root?.let { wm?.updateViewLayout(it, params!!) }
            // Update collapsed view size
            collapsedView?.let { view ->
                view.layoutParams = FrameLayout.LayoutParams(baseSize, baseSize)
                if (view is FrameLayout && view.childCount > 0) {
                    view.getChildAt(0).layoutParams = FrameLayout.LayoutParams(baseSize, baseSize)
                }
            }
        } else {
            // For expanded, just update params
            params?.width = ViewGroup.LayoutParams.WRAP_CONTENT
            params?.height = ViewGroup.LayoutParams.WRAP_CONTENT
            root?.let { wm?.updateViewLayout(it, params!!) }
        }
    }

    private fun refreshProfile() {
        scope.launch {
            val profile = RootShell.readCurrentState() ?: "balanced"
            activeProfile = profile
            ui.post {
                collapsedView?.invalidate()
                updateExpandedView()
            }
        }
    }

    private fun dpToPx(dp: Float): Int = (dp * resources.displayMetrics.density).toInt()
}