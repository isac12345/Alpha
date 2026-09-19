package com.alphabubble.ui.tuning

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.AdapterView
import android.widget.ArrayAdapter
import android.widget.Button
import android.widget.Spinner
import android.widget.TextView
import androidx.fragment.app.Fragment
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import com.alphabubble.LogFormat
import com.alphabubble.R
import com.alphabubble.RootShell
import kotlinx.coroutines.launch

class TuningFragment : Fragment(R.layout.fragment_tuning) {

    private var spRender: Spinner? = null
    private var btnRenderApply: Button? = null
    private var tvRenderStatus: TextView? = null
    private var rvLog: androidx.recyclerview.widget.RecyclerView? = null
    private var tvLogEmpty: TextView? = null
    private var btnLogAll: Button? = null
    private var tvDevice: TextView? = null
    private var btnRedetect: Button? = null

    private var renderOptions: List<String> = emptyList()
    private var logAdapter: LogAdapter? = null

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        spRender = view.findViewById(R.id.spRender)
        btnRenderApply = view.findViewById(R.id.btnRenderApply)
        tvRenderStatus = view.findViewById(R.id.tvRenderStatus)
        rvLog = view.findViewById(R.id.rvLog)
        tvLogEmpty = view.findViewById(R.id.tvLogEmpty)
        btnLogAll = view.findViewById(R.id.btnLogAll)
        tvDevice = view.findViewById(R.id.tvDevice)
        btnRedetect = view.findViewById(R.id.btnRedetect)

        rvLog?.layoutManager = LinearLayoutManager(requireContext())
        logAdapter = LogAdapter()
        rvLog?.adapter = logAdapter

        btnRenderApply?.setOnClickListener {
            val selected = spRender?.selectedItem as String?
            selected?.let { applyRender(it) }
        }

        btnLogAll?.setOnClickListener {
            LogAllDialog().show(childFragmentManager, "log_all")
        }

        btnRedetect?.setOnClickListener {
            redetect()
        }

        loadRender()
        loadLog()
        loadDevice()
    }

    private fun loadRender() {
        lifecycleScope.launch {
            val info = RootShell.renderGet()
            requireActivity().runOnUiThread {
                renderOptions = info?.backends ?: listOf("default")
                val active = info?.backend ?: "default"
                val adapter = ArrayAdapter(requireContext(), R.layout.spinner_item, renderOptions)
                adapter.setDropDownViewResource(R.layout.spinner_dropdown_item)
                spRender?.adapter = adapter
                spRender?.setSelection(renderOptions.indexOf(active).coerceAtLeast(0))
                tvRenderStatus?.text = "Aktif: $active"
            }
        }
    }

    private fun applyRender(backend: String) {
        lifecycleScope.launch {
            val result = RootShell.renderSet(backend)
            if (result.success) {
                loadRender()
            }
        }
    }

    private fun loadLog() {
        lifecycleScope.launch {
            val logs = RootShell.tailLog(5)
            requireActivity().runOnUiThread {
                logAdapter?.submitList(logs)
                tvLogEmpty?.visibility = if (logs.isEmpty()) View.VISIBLE else View.GONE
            }
        }
    }

    private fun loadDevice() {
        lifecycleScope.launch {
            val result = RootShell.deviceInfo(requireContext(), false)
            requireActivity().runOnUiThread {
                if (result.success) {
                    tvDevice?.text = result.out.joinToString("\n")
                } else {
                    tvDevice?.text = "Gagal baca device info"
                }
            }
        }
    }

    private fun redetect() {
        btnRedetect?.isEnabled = false
        lifecycleScope.launch {
            val result = RootShell.redetect(requireContext(), true)
            requireActivity().runOnUiThread {
                btnRedetect?.isEnabled = true
                loadDevice()
            }
        }
    }
}

class LogAdapter : androidx.recyclerview.widget.ListAdapter<RootShell.LogEntry, LogAdapter.VH>(LogDiffCallback()) {
    class VH(view: View) : RecyclerView.ViewHolder(view) {
        val tvTime: TextView = view.findViewById(R.id.tvLogTime)
        val tvStatus: TextView = view.findViewById(R.id.tvLogStatus)
        val tvMsg: TextView = view.findViewById(R.id.tvLogMsg)
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

    class LogDiffCallback : DiffUtil.ItemCallback<RootShell.LogEntry>() {
        override fun areItemsTheSame(oldItem: RootShell.LogEntry, newItem: RootShell.LogEntry): Boolean =
            oldItem.detail == newItem.detail && oldItem.status == newItem.status

        override fun areContentsTheSame(oldItem: RootShell.LogEntry, newItem: RootShell.LogEntry): Boolean =
            oldItem == newItem
    }
}