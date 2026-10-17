package de.dorfspy.schulpilot

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val updater by lazy { AppUpdater(this) }
    private var notificationChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val notifications = PushNotifications(this)
        notifications.createChannel()
        notificationChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "de.dorfspy.schulpilot/notifications").also { it.setMethodCallHandler(notifications::handle) }
    }

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
        setIntent(intent)
        if (intent.getBooleanExtra(PushNotifications.OPEN, false)) {
            intent.removeExtra(PushNotifications.OPEN)
            notificationChannel?.invokeMethod("open", null)
        }
        updater.onStart()
    }

    override fun onDestroy() {
        notificationChannel?.setMethodCallHandler(null)
        notificationChannel = null
        updater.close()
        super.onDestroy()
    }
}
