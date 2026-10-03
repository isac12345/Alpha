package com.alphabubble
import android.os.Bundle
import android.widget.Toast
import android.app.Activity
class MainActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) { super.onCreate(savedInstanceState); setContentView(R.layout.activity_main); Toast.makeText(this,"Alpha Control v1 · fusion", Toast.LENGTH_SHORT).show() }
}
