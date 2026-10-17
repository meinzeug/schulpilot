package de.dorfspy.schulpilot

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import android.net.Uri
import android.provider.Settings
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Fixed neutral presentation only. No tokens, user content or arbitrary URLs. */
class PushNotifications(private val activity: MainActivity) {
    companion object {
        const val CHANNEL = "schulpilot_updates_v1"
        const val OPEN = "schulpilot_open_notifications"
    }
    private val manager = activity.getSystemService(NotificationManager::class.java)

    fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(CHANNEL, "Lernen & Familie", NotificationManager.IMPORTANCE_HIGH)
            channel.description = "Neutrale Hinweise zu vorbereiteten Lernrunden und Familiennachrichten"
            channel.lockscreenVisibility = Notification.VISIBILITY_PRIVATE
            // Quiet by default; Android's per-channel choices remain authoritative.
            channel.setSound(null, null)
            channel.enableVibration(false)
            manager.createNotificationChannel(channel)
        }
    }

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "status" -> result.success(mapOf(
                    "available" to true,
                    "permission" to manager.areNotificationsEnabled(),
                    "channel" to (Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
                        manager.getNotificationChannel(CHANNEL)?.importance != NotificationManager.IMPORTANCE_NONE)
                ))
                "settings" -> {
                    val channelBlocked = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                        manager.getNotificationChannel(CHANNEL)?.importance == NotificationManager.IMPORTANCE_NONE
                    val action = if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) Settings.ACTION_APPLICATION_DETAILS_SETTINGS
                        else if (channelBlocked) Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS else Settings.ACTION_APP_NOTIFICATION_SETTINGS
                    activity.startActivity(Intent(action).apply {
                        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) data = Uri.parse("package:" + activity.packageName)
                        putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName)
                        if (channelBlocked) putExtra(Settings.EXTRA_CHANNEL_ID, CHANNEL)
                    })
                    result.success(null)
                }
                "show" -> {
                    if (manager.areNotificationsEnabled()) {
                        val intent = Intent(activity, MainActivity::class.java).apply {
                            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
                            putExtra(OPEN, true)
                        }
                        val pending = PendingIntent.getActivity(activity, 7041, intent,
                            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                            Notification.Builder(activity, CHANNEL) else Notification.Builder(activity)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) builder.setTimeoutAfter(60_000)
                        manager.notify("schulpilot", 7041, builder
                            .setSmallIcon(R.drawable.ic_notification)
                            .setContentTitle("SCHULPILOT")
                            .setContentText("Es gibt Neuigkeiten in SCHULPILOT. Öffne deinen Lernraum.")
                            .setVisibility(Notification.VISIBILITY_PRIVATE)
                            .setContentIntent(pending).setAutoCancel(true).setOnlyAlertOnce(true).build())
                    }
                    result.success(null)
                }
                "initialOpen" -> {
                    val open = activity.intent.getBooleanExtra(OPEN, false)
                    activity.intent.removeExtra(OPEN)
                    result.success(open)
                }
                "clear" -> { manager.cancelAll(); result.success(null) }
                else -> result.notImplemented()
            }
        } catch (_: Exception) {
            result.error("NOTIFICATIONS_UNAVAILABLE", "Android-Benachrichtigungen konnten nicht geöffnet werden.", null)
        }
    }
}
