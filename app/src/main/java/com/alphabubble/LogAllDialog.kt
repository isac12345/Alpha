package com.alphabubble

import android.app.AlertDialog
import android.app.Dialog
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.fragment.app.DialogFragment
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import com.alphabubble.R
import com.alphabubble.RootShell
import kotlinx.coroutines.launch

class LogAllDialog : DialogFragment() {

    private var rvLog: androidx.recyclerview.widget.RecyclerView? = null
    private var adapter: LogAdapter? = null

    override fun onCreateDialog(savedInstanceState: Bundle?): Dialog {
        val view = LayoutInflater.from(requireContext()).inflate(R.layout.dialog_log_all, null)
        rvLog = view.findViewById(R.id.rvLogAll)

        rvLog?.layoutManager = LinearLayoutManager(requireContext())
        adapter = LogAdapter()
        rvLog?.adapter = adapter

        loadLogs()

        return AlertDialog.Builder(requireContext())
            .setTitle("Semua Log Tuning")
            .setView(view)
            .setPositiveButton("Tutup", null)
            .create()
    }

    private fun loadLogs() {
        lifecycleScope.launch {
            val logs = RootShell.fullLog(200)
            requireActivity().runOnUiThread {
                adapter?.submitList(logs)
            }
        }
    }

    class LogAdapter : androidx.recyclerview.widget.ListAdapter<RootShell.LogEntry, LogAdapter.VH>(LogDiffCallback()) {
        class VH(view: View) : androidx.recyclerview.widget.RecyclerView.ViewHolder(view) {
            val tvTime: android.widget.TextView = view.findViewById(R.id.tvLogTime)
            val tvStatus: android.widget.TextView = view.findViewById(R.id.tvLogStatus)
            val tvMsg: android.widget.TextView = view.findViewById(R.id.tvLogMsg)
        }

        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): VH {
            val view = LayoutInflater.from(parent.context).inflate(R.layout.item_log, parent, false)
            return VH(view)
        }

        override fun onBindViewHolder(holder: VH, position: Int) {
            val entry = getItem(position)
            val compact = LogFormat.compact(entry.detail)
            holder.tvTime.text = compact.time
            holder.tvStatus.text = compact.status
            holder.tvMsg.text = compact.message
        }

        class LogDiffCallback : androidx.recyclerview.widget.DiffUtil.ItemCallback<RootShell.LogEntry>() {
            override fun areItemsTheSame(oldItem: RootShell.LogEntry, newItem: RootShell.LogEntry): Boolean =
                oldItem.detail == newItem.detail && oldItem.status == newItem.status

            override fun areContentsTheSame(oldItem: RootShell.LogEntry, newItem: RootShell.LogEntry): Boolean =
                oldItem == newItem
        }
    }
}