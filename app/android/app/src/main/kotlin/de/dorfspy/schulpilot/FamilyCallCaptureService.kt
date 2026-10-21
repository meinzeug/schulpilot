package de.dorfspy.schulpilot

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import io.flutter.plugin.common.MethodChannel

/** Lifecycle container only. It never obtains a camera, microphone or projection. */
class FamilyCallCaptureService : Service() {
    companion object {
        private const val CHANNEL = "schulpilot_active_call_v1"
        private const val NOTIFICATION = 7056
        private var pending: MethodChannel.Result? = null
        private var pendingCallId: String? = null
        var activeCallId: String? = null
            private set

        fun start(context: Context, callId: String, camera: Boolean, microphone: Boolean,
                  projection: Boolean, result: MethodChannel.Result) {
            if (!FamilyCallPolicy.validId(callId) || pending != null) {
                result.error("CALL_CAPTURE_UNAVAILABLE", "Die Übertragung konnte nicht gestartet werden.", null)
                return
            }
            pending = result
            pendingCallId = callId
            try {
                val intent = Intent(context, FamilyCallCaptureService::class.java)
                    .putExtra("call_id", callId).putExtra("camera", camera)
                    .putExtra("microphone", microphone).putExtra("projection", projection)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) context.startForegroundService(intent)
                else context.startService(intent)
            } catch (_: Exception) {
                pending?.error("CALL_CAPTURE_UNAVAILABLE", "Android erlaubt die Übertragung gerade nicht.", null)
                pending = null
                pendingCallId = null
            }
        }

        fun stop(context: Context, callId: String? = null) {
            if (!FamilyCallPolicy.mayStop(callId, activeCallId, pendingCallId)) return
            pending?.error("CALL_CAPTURE_CANCELLED", "Die Übertragung wurde beendet.", null)
            pending = null
            pendingCallId = null
            activeCallId = null
            context.stopService(Intent(context, FamilyCallCaptureService::class.java))
        }
    }

    private var types = 0
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val callId = intent?.getStringExtra("call_id")
        if (!FamilyCallPolicy.validId(callId)) {
            pending?.error("CALL_CAPTURE_UNAVAILABLE", "Die Übertragung konnte nicht gestartet werden.", null)
            pending = null
            pendingCallId = null
            stopSelf()
            return START_NOT_STICKY
        }
        try {
            val manager = getSystemService(NotificationManager::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) manager.createNotificationChannel(
                NotificationChannel(CHANNEL, "Aktive Live-Hilfe", NotificationManager.IMPORTANCE_LOW).apply {
                    setSound(null, null)
                    description = "Sichtbarer Hinweis während einer bewusst gestarteten Übertragung"
                })
            val open = PendingIntent.getActivity(this, NOTIFICATION, Intent(this, MainActivity::class.java).apply {
                this.flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
                action = "$packageName.family_call.$callId.active"
                putExtra(FamilyCallNotifications.OPEN, callId)
                putExtra(FamilyCallNotifications.ACTION, "open")
            }, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.Builder(this, CHANNEL)
                else Notification.Builder(this)
            val notification = builder.setSmallIcon(R.drawable.ic_notification)
                .setContentTitle("SCHULPILOT · Live-Hilfe aktiv")
                .setContentText("Zur Übertragung zurückkehren oder sie in der App beenden.")
                .setContentIntent(open).setCategory(Notification.CATEGORY_CALL)
                .setVisibility(Notification.VISIBILITY_PRIVATE).setOngoing(true).build()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                if (intent!!.getBooleanExtra("projection", false)) types = types or ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    if (intent.getBooleanExtra("camera", false)) types = types or ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA
                    if (intent.getBooleanExtra("microphone", false)) types = types or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
                }
                // Android10 has no camera/microphone type yet; explicit NONE
                // avoids falling back to the manifest's projection type.
                startForeground(NOTIFICATION, notification, types)
            } else startForeground(NOTIFICATION, notification)
            activeCallId = callId
            pending?.success(null)
            pending = null
            pendingCallId = null
        } catch (_: Exception) {
            pending?.error("CALL_CAPTURE_UNAVAILABLE", "Android erlaubt die Übertragung gerade nicht. Prüfe die Kamera- und Mikrofonfreigabe.", null)
            pending = null
            pendingCallId = null
            stopSelf()
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        types = 0
        activeCallId = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }
}
