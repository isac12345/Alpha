package com.alphabubble.ui.about

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.TextView
import androidx.fragment.app.Fragment
import androidx.lifecycle.lifecycleScope
import com.alphabubble.R
import com.alphabubble.RootShell
import kotlinx.coroutines.launch

class AboutFragment : Fragment(R.layout.fragment_about) {

    private var tvVersion: TextView? = null
    private var tvModule: TextView? = null
    private var btnBatteryLab: Button? = null
    private var btnRescan: Button? = null
    private var btnRefresh: Button? = null

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        tvVersion = view.findViewById(R.id.tvVersion)
        tvModule = view.findViewById(R.id.tvModule)
        btnBatteryLab = view.findViewById(R.id.btnBatteryLab)
        btnRescan = view.findViewById(R.id.btnRescan)
        btnRefresh = view.findViewById(R.id.btnRefresh)

        tvVersion?.text = "Alpha Control v2.0"

        btnBatteryLab?.setOnClickListener {
            try {
                val intent = Intent(Intent.ACTION_VIEW, Uri.parse("batterylab://"))
                startActivity(intent)
            } catch (e: Exception) {
                // Battery Lab not installed
            }
        }

        btnRescan?.setOnClickListener {
            rescanModule()
        }

        btnRefresh?.setOnClickListener {
            refreshAll()
        }

        refreshModule()
    }

    private fun refreshModule() {
        lifecycleScope.launch {
            val modulePath = RootShell.findModulePath(requireContext())
            requireActivity().runOnUiThread {
                tvModule?.text = if (modulePath != null) "Module: $modulePath" else "Module: NOT FOUND"
            }
        }
    }

    private fun rescanModule() {
        btnRescan?.isEnabled = false
        lifecycleScope.launch {
            RootShell.findModulePath(requireContext())
            requireActivity().runOnUiThread {
                btnRescan?.isEnabled = true
                refreshModule()
            }
        }
    }

    private fun refreshAll() {
        lifecycleScope.launch {
            RootShell.redetect(requireContext(), true)
            requireActivity().runOnUiThread {
                refreshModule()
            }
        }
    }
}