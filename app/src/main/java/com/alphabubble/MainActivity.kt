package com.alphabubble

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import androidx.fragment.app.Fragment
import com.alphabubble.ui.about.AboutFragment
import com.alphabubble.ui.display.DisplayFragment
import com.alphabubble.ui.games.GamesFragment
import com.alphabubble.ui.home.HomeFragment
import com.alphabubble.ui.tuning.TuningFragment
import com.google.android.material.bottomnavigation.BottomNavigationView

class MainActivity : AppCompatActivity() {

    private lateinit var bottomNav: BottomNavigationView

    private val fragments: List<Fragment> = listOf(
        HomeFragment(),
        GamesFragment(),
        TuningFragment(),
        DisplayFragment(),
        AboutFragment()
    )

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        bottomNav = findViewById(R.id.bottomNav)
        bottomNav.setOnItemSelectedListener { item ->
            when (item.itemId) {
                R.id.nav_home -> switchFragment(0)
                R.id.nav_games -> switchFragment(1)
                R.id.nav_tuning -> switchFragment(2)
                R.id.nav_display -> switchFragment(3)
                R.id.nav_about -> switchFragment(4)
                else -> return@setOnItemSelectedListener false
            }
            true
        }

        if (savedInstanceState == null) {
            switchFragment(0)
        }
    }

    private fun switchFragment(index: Int) {
        supportFragmentManager.beginTransaction()
            .setCustomAnimations(R.anim.fragment_fade_in, R.anim.fragment_fade_out)
            .replace(R.id.fragmentContainer, fragments[index])
            .commit()
    }
}