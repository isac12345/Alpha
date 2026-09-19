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
import kotlinx.coroutines.launch

class AddGameDialog : DialogFragment() {

    private var adapter: AppAdapter? = null
    private var etSearch: EditText? = null
    private var spProfile: Spinner? = null
    private var allApps: List<AppRow> = emptyList()
    private var onGameAddedListener: OnGameAddedListener? = null

    data class AppRow(
        val info: ApplicationInfo,
        val label: String,
        val isHeader: Boolean = false
    )

    fun interface OnGameAddedListener {
        fun onGameAdded(packageName: String, profile: String)
    }

    fun setOnGameAddedListener(listener: OnGameAddedListener) {
        onGameAddedListener = listener
    }

    override fun onCreateDialog(savedInstanceState: Bundle?): Dialog {
        val view = LayoutInflater.from(requireContext()).inflate(R.layout.dialog_add_game, null)
        etSearch = view.findViewById(R.id.etSearch)
        spProfile = view.findViewById(R.id.spProfile)
        val rvApps = view.findViewById<androidx.recyclerview.widget.RecyclerView>(R.id.rvApps)

        val profiles = arrayOf("battery", "balanced", "performance")
        val profileAdapter = ArrayAdapter(requireContext(), R.layout.spinner_item, profiles.map { NotifHelper.labelFor(it) })
        profileAdapter.setDropDownViewResource(R.layout.spinner_dropdown_item)
        spProfile?.adapter = profileAdapter

        rvApps.layoutManager = LinearLayoutManager(requireContext())
        adapter = AppAdapter(requireContext(), { allApps }) { row ->
            if (!row.isHeader) {
                val profile = profiles[spProfile?.selectedItemPosition ?: 1]
                dismiss()
                onGameAddedListener?.onGameAdded(row.info.packageName, profile)
            }
        }
        rvApps.adapter = adapter

        loadApps()

        etSearch?.addTextChangedListener { adapter?.filter(it.toString()) }

        return AlertDialog.Builder(requireContext())
            .setTitle("Tambah Game")
            .setView(view)
            .setNegativeButton("Batal", null)
            .create()
    }

    private fun loadApps() {
        lifecycleScope.launch {
            val pm = requireContext().packageManager
            val apps = pm.getInstalledApplications(PackageManager.GET_META_DATA)
            val rows = mutableListOf<AppRow>()
            rows.add(AppRow(ApplicationInfo(), "=== SYSTEM APPS ===", true))
            for (app in apps) {
                if ((app.flags and ApplicationInfo.FLAG_SYSTEM) != 0) {
                    val label = pm.getApplicationLabel(app).toString()
                    rows.add(AppRow(app, label))
                }
            }
            rows.add(AppRow(ApplicationInfo(), "=== USER APPS ===", true))
            for (app in apps) {
                if ((app.flags and ApplicationInfo.FLAG_SYSTEM) == 0) {
                    val label = pm.getApplicationLabel(app).toString()
                    rows.add(AppRow(app, label))
                }
            }
            allApps = rows
            requireActivity().runOnUiThread {
                adapter?.submitList(rows)
            }
        }
    }

    class AppAdapter(
        private val ctx: android.content.Context,
        private val getAll: () -> List<AppRow>,
        private val onClick: (AppRow) -> Unit
    ) : androidx.recyclerview.widget.ListAdapter<AppRow, AppAdapter.VH>(AppDiffCallback()) {

        class VH(view: View) : androidx.recyclerview.widget.RecyclerView.ViewHolder(view) {
            val tvLabel: android.widget.TextView = view.findViewById(R.id.tvAppLabel)
            val tvPkg: android.widget.TextView = view.findViewById(R.id.tvAppPkg)
        }

        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): VH {
            val layout = if (viewType == 1) R.layout.item_app_header else R.layout.item_app
            val view = LayoutInflater.from(parent.context).inflate(layout, parent, false)
            return VH(view)
        }

        override fun getItemViewType(position: Int): Int =
            if (getItem(position).isHeader) 1 else 0

        override fun onBindViewHolder(holder: VH, position: Int) {
            val row = getItem(position)
            if (row.isHeader) {
                holder.tvLabel.text = row.label
            } else {
                holder.tvLabel.text = row.label
                holder.tvPkg.text = row.info.packageName
                holder.itemView.setOnClickListener { onClick(row) }
            }
        }

        fun filter(query: String) {
            val outer = getAll()
            if (query.isBlank()) {
                submitList(outer)
            } else {
                val filtered = outer.filter { it.isHeader || it.label.lowercase().contains(query.lowercase()) }
                submitList(filtered)
            }
        }

        class AppDiffCallback : androidx.recyclerview.widget.DiffUtil.ItemCallback<AppRow>() {
            override fun areItemsTheSame(oldItem: AppRow, newItem: AppRow): Boolean =
                oldItem.info.packageName == newItem.info.packageName && oldItem.isHeader == newItem.isHeader

            override fun areContentsTheSame(oldItem: AppRow, newItem: AppRow): Boolean =
                oldItem == newItem
        }
    }
}