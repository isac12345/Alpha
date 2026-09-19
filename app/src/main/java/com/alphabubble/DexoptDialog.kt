package com.alphabubble

import android.app.AlertDialog
import android.app.Dialog
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.AdapterView
import android.widget.ArrayAdapter
import android.widget.EditText
import android.widget.Spinner
import androidx.fragment.app.DialogFragment
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.core.widget.addTextChangedListener
import com.alphabubble.R
import com.alphabubble.RootShell
import kotlinx.coroutines.launch

class DexoptDialog : DialogFragment() {

    private var etSearch: EditText? = null
    private var spMode: Spinner? = null
    private var rvApps: androidx.recyclerview.widget.RecyclerView? = null
    private var adapter: AppAdapter? = null
    private var allApps: List<ApplicationInfo> = emptyList()
    private var filteredApps: List<ApplicationInfo> = emptyList()

    override fun onCreateDialog(savedInstanceState: Bundle?): Dialog {
        val view = LayoutInflater.from(requireContext()).inflate(R.layout.dialog_dexopt, null)
        etSearch = view.findViewById(R.id.etSearch)
        spMode = view.findViewById(R.id.spMode)
        rvApps = view.findViewById(R.id.rvApps)

        val modes = arrayOf("speed", "speed-profile", "verify", "extract")
        val modeAdapter = ArrayAdapter(requireContext(), R.layout.spinner_item, modes)
        modeAdapter.setDropDownViewResource(R.layout.spinner_dropdown_item)
        spMode?.adapter = modeAdapter

        rvApps?.layoutManager = LinearLayoutManager(requireContext())
        adapter = AppAdapter(requireContext()) { info ->
            val mode = modes[spMode?.selectedItemPosition ?: 0]
            lifecycleScope.launch {
                val result = RootShell.dexopt(mode, info.packageName)
                // Optionally show result
            }
        }
        rvApps?.adapter = adapter

        loadApps()

        etSearch?.addTextChangedListener {
            filterApps(it.toString())
        }

        return AlertDialog.Builder(requireContext())
            .setTitle("Dexopt App")
            .setView(view)
            .setNegativeButton("Tutup", null)
            .create()
    }

    private fun loadApps() {
        lifecycleScope.launch {
            val pm = requireContext().packageManager
            val apps = pm.getInstalledApplications(PackageManager.GET_META_DATA)
                .filter { (it.flags and ApplicationInfo.FLAG_SYSTEM) == 0 }
                .sortedBy { pm.getApplicationLabel(it).toString() }
            allApps = apps
            filteredApps = apps
            requireActivity().runOnUiThread {
                adapter?.submitList(apps)
            }
        }
    }

    private fun filterApps(query: String) {
        val pm = requireContext().packageManager
        if (query.isBlank()) {
            filteredApps = allApps
        } else {
            filteredApps = allApps.filter { pm.getApplicationLabel(it).toString().lowercase().contains(query.lowercase()) }
        }
        adapter?.submitList(filteredApps)
    }

    class AppAdapter(
        private val ctx: android.content.Context,
        private val onClick: (ApplicationInfo) -> Unit
    ) : androidx.recyclerview.widget.ListAdapter<ApplicationInfo, AppAdapter.VH>(AppDiffCallback()) {

        class VH(view: View) : androidx.recyclerview.widget.RecyclerView.ViewHolder(view) {
            val tvLabel: android.widget.TextView = view.findViewById(R.id.tvAppLabel)
            val tvPkg: android.widget.TextView = view.findViewById(R.id.tvAppPkg)
        }

        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): VH {
            val view = LayoutInflater.from(parent.context).inflate(R.layout.item_app, parent, false)
            return VH(view)
        }

        override fun onBindViewHolder(holder: VH, position: Int) {
            val info = getItem(position)
            val pm = ctx.packageManager
            holder.tvLabel.text = pm.getApplicationLabel(info)
            holder.tvPkg.text = info.packageName
            holder.itemView.setOnClickListener { onClick(info) }
        }

        class AppDiffCallback : androidx.recyclerview.widget.DiffUtil.ItemCallback<ApplicationInfo>() {
            override fun areItemsTheSame(oldItem: ApplicationInfo, newItem: ApplicationInfo): Boolean =
                oldItem.packageName == newItem.packageName

            override fun areContentsTheSame(oldItem: ApplicationInfo, newItem: ApplicationInfo): Boolean =
                oldItem == newItem
        }
    }
}