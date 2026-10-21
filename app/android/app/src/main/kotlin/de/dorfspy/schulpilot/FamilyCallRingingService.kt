package de.dorfspy.schulpilot

import android.app.Notification
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper

/** At most45s of visible incoming-call handling. No media or new phone role. */
class FamilyCallRingingService : Service() {
    companion object {
        private var currentId: String? = null
        fun start(context: Context, callId: String, notification: Notification, ringMillis: Long): Boolean {
            currentId = callId
            return try {
                val intent = Intent(context, FamilyCallRingingService::class.java)
                    .putExtra("call_id", callId).putExtra("notification", notification)
                    .putExtra("ring_millis", ringMillis)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) context.startForegroundService(intent)
                else context.startService(intent)
                true
            } catch (_: Exception) { currentId = null; false }
        }
        fun stop(context: Context, callId: String? = null) {
            if (callId != null && callId != currentId) return
            currentId = null
            context.stopService(Intent(context, FamilyCallRingingService::class.java))
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val callId = intent?.getStringExtra("call_id")
        val notification = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU)
            intent?.getParcelableExtra("notification", Notification::class.java)
            else @Suppress("DEPRECATION") intent?.getParcelableExtra<Notification>("notification")
        if (!FamilyCallPolicy.validId(callId) || notification == null) {
            stopSelf()
            return START_NOT_STICKY
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
                startForeground(FamilyCallNotifications.ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SHORT_SERVICE)
            else startForeground(FamilyCallNotifications.ID, notification)
            if (currentId != callId) stopSelf()
            else Handler(Looper.getMainLooper()).postDelayed({
                if (currentId == callId) FamilyCallNotifications(this).cancel(callId!!)
            }, (intent?.getLongExtra("ring_millis", 0) ?: 0).coerceIn(1, FamilyCallPolicy.MAX_RING_MILLIS))
        } catch (_: Exception) {
            FamilyCallNotifications(this).fallback(callId!!, intent?.getLongExtra("ring_millis", 1) ?: 1)
            stopSelf()
        }
        return START_NOT_STICKY
    }
    override fun onTimeout(startId: Int) { stopSelf() }
    override fun onDestroy() {
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }
}
