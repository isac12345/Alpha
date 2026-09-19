package com.alphabubble.ui.games

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.EditText
import android.widget.TextView
import androidx.fragment.app.Fragment
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.core.widget.addTextChangedListener
import com.alphabubble.AddGameDialog
import com.alphabubble.R
import com.alphabubble.RootShell
import kotlinx.coroutines.launch

class GamesFragment : Fragment(R.layout.fragment_games) {

    private var rvGames: androidx.recyclerview.widget.RecyclerView? = null
    private var tvEmpty: TextView? = null
    private var etSearch: EditText? = null
    private var adapter: GameAdapter? = null

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        rvGames = view.findViewById(R.id.rvGames)
        tvEmpty = view.findViewById(R.id.tvGamesEmpty)
        etSearch = view.findViewById(R.id.etGameSearch)

        rvGames?.layoutManager = LinearLayoutManager(requireContext())
        adapter = GameAdapter(
            requireContext(),
            onProfileChange = { entry, profile ->
                lifecycleScope.launch {
                    val result = RootShell.addGameFlow(requireContext(), entry.packageName, profile)
                    if (result.success) loadGames()
                }
            },
            onRemove = { entry ->
                lifecycleScope.launch {
                    val result = RootShell.removeGameFlow(requireContext(), entry.packageName)
                    if (result.success) loadGames()
                }
            }
        )
        rvGames?.adapter = adapter

        view.findViewById<Button>(R.id.btnAddGame).setOnClickListener {
            val dialog = AddGameDialog()
            dialog.setOnGameAddedListener(object : AddGameDialog.OnGameAddedListener {
                override fun onGameAdded(pkg: String, profile: String) {
                    lifecycleScope.launch {
                        val result = RootShell.addGameFlow(requireContext(), pkg, profile)
                        if (result.success) loadGames()
                    }
                }
            })
            dialog.show(childFragmentManager, "add_game")
        }

        etSearch?.addTextChangedListener { adapter?.filter(it.toString()) }

        loadGames()
    }

    override fun onResume() {
        super.onResume()
        loadGames()
    }

    private fun loadGames() {
        lifecycleScope.launch {
            val games = RootShell.gameList(requireContext())
            requireActivity().runOnUiThread {
                adapter?.submitList(games)
                tvEmpty?.visibility = if (games.isEmpty()) View.VISIBLE else View.GONE
            }
        }
    }
}