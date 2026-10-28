package de.dorfspy.schulpilot

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Person
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingReceiver

/** All displayed strings are fixed. No family, subject or task content in push. */
class FamilyCallNotifications(private val context: Context) {
    companion object {
        const val CHANNEL = "schulpilot_family_calls_v1"
        const val OPEN = "schulpilot_family_call"
        const val ACTION = "schulpilot_family_call_action"
        private const val PREFS = "schulpilot_family_calls"
        const val ID = 7052
        private const val TAG = "schulpilot_family_call"
    }

    private val manager = context.getSystemService(NotificationManager::class.java)
    private val preferences = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val attributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build()
            manager.createNotificationChannel(NotificationChannel(CHANNEL,
                "Familienanrufe", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Eingehende Live-Hilfe nach ausdrücklicher Gerätefreigabe"
                lockscreenVisibility = Notification.VISIBILITY_PRIVATE
                setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE), attributes)
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 700, 700, 700)
            })
        }
    }

    fun bind(value: String?) {
        if (value != null && !FamilyCallPolicy.validBinding(value)) throw IllegalArgumentException()
        if (preferences.getString("binding", null) != value) clear()
        preferences.edit().apply {
            if (value == null) remove("binding") else putString("binding", value)
        }.apply()
    }

    fun bound() = FamilyCallPolicy.validBinding(preferences.getString("binding", null))

    fun receive(data: Map<String, String>, allowService: Boolean = true) {
        val binding = preferences.getString("binding", null)
        if (!FamilyCallPolicy.matches(data, binding)) return
        val callId = data["call_id"] ?: return
        if (!FamilyCallPolicy.validId(callId)) return
        if (data["event"] == "ended") {
            cancel(callId)
            return
        }
        FamilyCallPolicy.incoming(data, binding, System.currentTimeMillis())?.let { show(it, allowService) }
    }

    fun show(callId: String, expiresAt: Long) {
        val binding = preferences.getString("binding", null) ?: return
        FamilyCallPolicy.incoming(mapOf("type" to "family_call", "event" to "incoming",
            "call_id" to callId, "call_binding" to binding, "expires_at" to expiresAt.toString()),
            binding, System.currentTimeMillis())?.let { show(it) }
    }

    private fun activityIntent(callId: String, action: String, request: Int): PendingIntent =
        PendingIntent.getActivity(context, request, Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            this.action = "${context.packageName}.family_call.$callId.$action"
            putExtra(OPEN, callId)
            putExtra(ACTION, action)
        }, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

    private fun expiryIntent(callId: String): PendingIntent = PendingIntent.getBroadcast(context, ID,
        Intent(context, FamilyCallExpiryReceiver::class.java).apply {
            data = Uri.parse("schulpilot-internal://family-call/$callId/expire")
            putExtra(OPEN, callId)
        }, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

    private fun show(incoming: FamilyCallPolicy.Incoming, allowService: Boolean = true) {
        createChannel()
        if (!manager.areNotificationsEnabled() ||
            preferences.getStringSet("finished", emptySet())!!.contains(incoming.callId) ||
            preferences.getString("ringing", null) == incoming.callId) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            manager.getNotificationChannel(CHANNEL)?.importance == NotificationManager.IMPORTANCE_NONE) return
        preferences.getString("ringing", null)?.let { cancel(it) }
        preferences.edit().putString("ringing", incoming.callId).apply()
        val notification = build(incoming, styled = true)
        if (!allowService || !FamilyCallRingingService.start(context, incoming.callId, notification, incoming.ringMillis)) {
            // A downgraded FCM or blocked service must not crash or invoke a
            // fullscreen entitlement. A normal ringing notification remains.
            manager.notify(TAG, ID, build(incoming, styled = false))
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            context.getSystemService(AlarmManager::class.java).setExact(AlarmManager.ELAPSED_REALTIME_WAKEUP,
                SystemClock.elapsedRealtime() + incoming.ringMillis, expiryIntent(incoming.callId))
        }
        Handler(Looper.getMainLooper()).postDelayed({ cancel(incoming.callId) }, incoming.ringMillis)
    }

    private fun build(incoming: FamilyCallPolicy.Incoming, styled: Boolean): Notification {
        val open = activityIntent(incoming.callId, "open", 7053)
        val answer = activityIntent(incoming.callId, "answer", 7054)
        val decline = activityIntent(incoming.callId, "decline", 7055)
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            Notification.Builder(context, CHANNEL) else Notification.Builder(context)
        builder.setSmallIcon(R.drawable.ic_notification)
            .setContentTitle("SchuleSchlau · Live-Hilfe")
            .setContentText("Ein Familienanruf wartet auf dich.")
            .setVisibility(Notification.VISIBILITY_PRIVATE).setCategory(Notification.CATEGORY_CALL)
            .setContentIntent(open).setOnlyAlertOnce(true).setOngoing(true)
            .setPriority(Notification.PRIORITY_MAX)
        if (styled && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setStyle(Notification.CallStyle.forIncomingCall(
                Person.Builder().setName("SchuleSchlau · Familie").setImportant(true).build(), decline, answer))
        } else {
            builder.addAction(Notification.Action.Builder(null, "Ablehnen", decline).build())
                .addAction(Notification.Action.Builder(null, "Annehmen", answer).build())
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) builder.setTimeoutAfter(incoming.ringMillis)
        else builder.setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE))
            .setVibrate(longArrayOf(0, 700, 700, 700))
        return builder.build().apply { flags = flags or Notification.FLAG_INSISTENT }
    }

    fun fallback(callId: String, ringMillis: Long) {
        if (!bound() || preferences.getString("ringing", null) != callId || !manager.areNotificationsEnabled()) return
        val duration = ringMillis.coerceIn(1, FamilyCallPolicy.MAX_RING_MILLIS)
        manager.notify(TAG, ID, build(FamilyCallPolicy.Incoming(callId,
            System.currentTimeMillis() + duration, duration), styled = false))
    }

    fun cancel(callId: String) {
        if (!FamilyCallPolicy.validId(callId)) return
        val finished = preferences.getStringSet("finished", emptySet())!!.toMutableSet()
        finished.add(callId)
        preferences.edit().putStringSet("finished", finished.toList().takeLast(32).toSet()).apply()
        if (preferences.getString("ringing", null) == callId) {
            FamilyCallRingingService.stop(context, callId)
            manager.cancel(TAG, ID)
            manager.cancel(ID)
            preferences.edit().remove("ringing").apply()
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O)
            context.getSystemService(AlarmManager::class.java).cancel(expiryIntent(callId))
    }

    fun clear() {
        FamilyCallRingingService.stop(context)
        manager.cancel(TAG, ID)
        manager.cancel(ID)
        preferences.getString("ringing", null)?.let { cancel(it) }
        preferences.edit().clear().apply()
    }

    fun takeIntent(intent: Intent): Map<String, String>? {
        val callId = intent.getStringExtra(OPEN)
        val action = intent.getStringExtra(ACTION) ?: "open"
        intent.removeExtra(OPEN)
        intent.removeExtra(ACTION)
        if ((!bound() && FamilyCallCaptureService.activeCallId != callId) ||
            !FamilyCallPolicy.validId(callId) || !FamilyCallPolicy.validAction(action)) return null
        cancel(callId!!)
        return mapOf("call_id" to callId, "action" to action)
    }

    fun status(): Map<String, Any> {
        createChannel()
        val channel = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) manager.getNotificationChannel(CHANNEL) else null
        val audio = context.getSystemService(AudioManager::class.java)
        val audible = audio.ringerMode == AudioManager.RINGER_MODE_NORMAL &&
            audio.getStreamVolume(AudioManager.STREAM_RING) > 0 &&
            manager.currentInterruptionFilter == NotificationManager.INTERRUPTION_FILTER_ALL
        return mapOf("available" to true, "permission" to manager.areNotificationsEnabled(),
            "enabled" to bound(), "channel" to (channel == null || channel.importance != NotificationManager.IMPORTANCE_NONE),
            "sound" to (channel == null || channel.sound != null),
            "heads_up" to (channel == null || channel.importance >= NotificationManager.IMPORTANCE_HIGH),
            "audible" to audible,
            "full_screen" to false)
    }

    fun openSettings() {
        createChannel()
        context.startActivity(Intent(if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS else Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) data = Uri.parse("package:" + context.packageName)
            putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
            putExtra(Settings.EXTRA_CHANNEL_ID, CHANNEL)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        })
    }
}

/** Signature-protected FCM receiver; other messages retain FlutterFire behavior. */
class FamilyCallMessagingReceiver : FlutterFirebaseMessagingReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.getStringExtra("type") != "family_call") {
            // FlutterFire uses goAsync(). Keep Android's PendingResult on the
            // framework-created receiver instead of delegating to a new instance.
            super.onReceive(context, intent)
            return
        }
        val data = listOf("type", "event", "call_id", "call_binding", "expires_at")
            .mapNotNull { key -> intent.getStringExtra(key)?.let { key to it } }.toMap()
        val highPriority = FamilyCallPolicy.highPriority(
            intent.getStringExtra("google.delivered_priority"),
            intent.getStringExtra("google.priority_reduced"),
            intent.getStringExtra("google.priority"))
        try { FamilyCallNotifications(context).receive(data, allowService = highPriority) } catch (_: Exception) {
            // Notifications/permissions may be revoked while a push is in flight.
            // No private values are logged and no media process is started.
        }
    }
}

class FamilyCallExpiryReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        intent.getStringExtra(FamilyCallNotifications.OPEN)?.let { FamilyCallNotifications(context).cancel(it) }
    }
}
