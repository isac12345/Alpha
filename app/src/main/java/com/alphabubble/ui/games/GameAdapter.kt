package com.alphabubble.ui.games

import android.content.Context
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.TextView
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.alphabubble.NotifHelper
import com.alphabubble.R
import com.alphabubble.RootShell

class GameAdapter(
    private val ctx: Context,
    private val onProfileChange: (RootShell.GameEntry, String) -> Unit,
    private val onRemove: (RootShell.GameEntry) -> Unit
) : ListAdapter<RootShell.GameEntry, GameAdapter.VH>(DiffCallback()) {

    class VH(view: View) : RecyclerView.ViewHolder(view) {
        val tvLabel: TextView = view.findViewById(R.id.tvGameLabel)
        val tvPkg: TextView = view.findViewById(R.id.tvGamePkg)
        val btnProfile: Button = view.findViewById(R.id.btnGameProfile)
        val btnRemove: Button = view.findViewById(R.id.btnGameRemove)
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): VH {
        val view = LayoutInflater.from(parent.context).inflate(R.layout.item_game, parent, false)
        return VH(view)
    }

    override fun onBindViewHolder(holder: VH, position: Int) {
        val entry = getItem(position)
        holder.tvLabel.text = entry.label
        holder.tvPkg.text = entry.packageName

        val currentProfile = entry.profile ?: "balanced"
        holder.btnProfile.text = NotifHelper.labelFor(currentProfile)
        holder.btnProfile.setOnClickListener {
            val profiles = NotifHelper.PROFILES
            val currentIndex = profiles.indexOf(currentProfile)
            val nextProfile = profiles[(currentIndex + 1) % profiles.size]
            onProfileChange(entry, nextProfile)
        }

        holder.btnRemove.setOnClickListener { onRemove(entry) }
    }

    fun filter(query: String) {
        // Filtering handled by submitting filtered list from fragment
    }

    class DiffCallback : DiffUtil.ItemCallback<RootShell.GameEntry>() {
        override fun areItemsTheSame(oldItem: RootShell.GameEntry, newItem: RootShell.GameEntry): Boolean =
            oldItem.packageName == newItem.packageName

        override fun areContentsTheSame(oldItem: RootShell.GameEntry, newItem: RootShell.GameEntry): Boolean =
            oldItem == newItem
    }
}