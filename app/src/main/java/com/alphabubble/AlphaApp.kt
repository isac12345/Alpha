package com.alphabubble

import android.app.Application
import com.topjohnwu.superuser.Shell

class AlphaApp : Application() {
    override fun onCreate() {
        super.onCreate()
        Shell.Builder.create()
            .setFlags(Shell.Builder.FLAG_REDIRECT_STDERR)
            .setTimeout(10_000)
            .setDefaultBuilder()
    }
}