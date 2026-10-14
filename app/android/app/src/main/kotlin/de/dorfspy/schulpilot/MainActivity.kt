package de.dorfspy.schulpilot

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    private val updater by lazy { AppUpdater(this) }

    override fun onStart() {
        super.onStart()
        // Every cold start AND every return from the background. No TTL.
        updater.onStart()
    }

    override fun onStop() {
        updater.onStop()
        super.onStop()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        updater.onStart()
    }

    override fun onDestroy() {
        updater.close()
        super.onDestroy()
    }
}
