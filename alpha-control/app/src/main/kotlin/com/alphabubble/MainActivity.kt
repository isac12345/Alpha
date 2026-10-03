package com.alphabubble
import android.app.Activity
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.View
import android.widget.*
class MainActivity : Activity() {
    private val handler = Handler(Looper.getMainLooper())
    private lateinit var banner: FrameLayout
    private val tabs = listOf("DASH","GAMES","CUSTOM","TOOLS")
    private val contents = mutableListOf<View>()
    private val navPills = mutableListOf<TextView>()
    override fun onCreate(s: Bundle?) { super.onCreate(s); setContentView(R.layout.activity_main)
        banner = findViewById(R.id.banner)
        val container = findViewById<LinearLayout>(R.id.content)
        val nav = findViewById<LinearLayout>(R.id.nav)
        tabs.forEachIndexed { i, t ->
            val pill = TextView(this).apply { text = t; textSize = 10f; setTextColor(0xFF87878A.toInt()); setBackgroundResource(R.drawable.pill_outline); setPadding(16,8,16,8); isClickable = true }
            pill.setOnClickListener { switchTab(i) }
            nav.addView(pill); navPills.add(pill)
            contents.add(buildTab(i))
            container.addView(contents[i]); contents[i].visibility = View.GONE
        }
        switchTab(0)
        startRefresh()
    }
    private fun switchTab(i: Int) {
        contents.forEachIndexed { idx, v -> v.visibility = if (idx==i) View.VISIBLE else View.GONE }
        navPills.forEachIndexed { idx, p ->
            if (idx==i) { p.setTextColor(0xFF0A0A0A.toInt()); p.setBackgroundResource(R.drawable.pill_solid) }
            else { p.setTextColor(0xFF87878A.toInt()); p.setBackgroundResource(R.drawable.pill_outline) }
        }
    }
    private fun buildTab(i: Int): View = when(i) {
        0 -> buildDash(); 1 -> buildGames(); 2 -> buildCustom(); else -> buildTools()
    }
    private fun buildDash(): ScrollView = ScrollView(this).apply { addView(LinearLayout(this@MainActivity).apply { orientation = LinearLayout.VERTICAL; addView(card("BUBBLE", "Saklar Bubble }) }
Overlay . Notifikasi"))
    private fun buildGames(): ScrollView = ScrollView(this).apply { addView(LinearLayout(this@MainActivity).apply { orientation = LinearLayout.VERTICAL; addView(card("GAME","Cari game · item pak + chip")) }) }
    private fun buildCustom(): ScrollView = ScrollView(this).apply { addView(LinearLayout(this@MainActivity).apply { orientation = LinearLayout.VERTICAL; addView(card("CUSTOMIZE","Background · Icon · HUD")) }) }
    private fun buildTools(): ScrollView = ScrollView(this).apply { addView(LinearLayout(this@MainActivity).apply { orientation = LinearLayout.VERTICAL; addView(card("TOOLS","Resolusi · Tuning · Engine · Device")) }) }
    private fun card(title:String, body:String): LinearLayout = LinearLayout(this).apply {
        val t = TextView(this@MainActivity).apply { text=title; textSize=14f; setTextColor(0xFFF4F2EE.toInt()); setTypeface(android.graphics.Typeface.MONOSPACE) }
        val b = TextView(this@MainActivity).apply { text=body; textSize=12f; setTextColor(0xFF87878A.toInt()) }
        orientation = LinearLayout.VERTICAL; setBackgroundResource(R.drawable.card_bg); setPadding(20,20,20,20)
        addView(t); addView(b)
    }
    private fun startRefresh() {
        handler.postDelayed(object : Runnable { override fun run() {
            if (contents.getOrNull(0)?.visibility == View.VISIBLE) { Toast.makeText(this@MainActivity,"Refresh DASH", Toast.LENGTH_SHORT).show() }
            handler.postDelayed(this, 5000)
        }}, 5000)
    }
}
