package de.dorfspy.schulpilot.qa

import android.app.Activity
import android.app.Instrumentation
import android.app.Notification
import android.app.NotificationManager
import android.content.Intent
import android.os.Bundle
import de.dorfspy.schulpilot.FamilyCallNotifications

/** Operator-owned emulator only; absent from every distributed APK/AAB. */
class FamilyCallInstrumentation : Instrumentation() {
    private var pushReceiverOnly = false

    override fun onCreate(arguments: Bundle?) {
        super.onCreate(arguments)
        pushReceiverOnly = arguments?.getString("mode") == "push_receiver"
        start()
    }

    override fun onStart() {
        if (pushReceiverOnly) {
            PushReceiverRegression(this).run()
            return
        }
        val result = Bundle()
        val presenter = FamilyCallNotifications(targetContext)
        val manager = targetContext.getSystemService(NotificationManager::class.java)
        val binding = "a".repeat(64)
        val callId = "b".repeat(32)
        fun active() = manager.activeNotifications.filter { it.id == FamilyCallNotifications.ID }
        fun deliver(id: String, event: String = "incoming", token: String = binding, expiry: Long = System.currentTimeMillis() + 45_000) {
            runOnMainSync { presenter.receive(mapOf("type" to "family_call", "event" to event,
                "call_id" to id, "call_binding" to token, "expires_at" to expiry.toString())) }
        }
        try {
            startActivitySync(Intent().setClassName(targetContext, "de.dorfspy.schulpilot.MainActivity")
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            waitForIdleSync()
            runOnMainSync { presenter.clear(); presenter.bind(binding) }
            deliver(callId, token = "c".repeat(64))
            check(active().isEmpty()) { "stale_account_rang" }
            deliver(callId, expiry = System.currentTimeMillis() - 1)
            check(active().isEmpty()) { "expired_call_rang" }
            deliver(callId)
            val shownDeadline = System.currentTimeMillis() + 2000
            while (active().isEmpty() && System.currentTimeMillis() < shownDeadline) Thread.sleep(50)
            val shown = active().single().notification
            check(shown.flags and Notification.FLAG_INSISTENT != 0) { "not_ringing_style" }
            check(shown.category == Notification.CATEGORY_CALL) { "wrong_category" }
            check(shown.extras.getString("android.template")?.endsWith("CallStyle") == true) { "not_call_style" }
            val channel = manager.getNotificationChannel(FamilyCallNotifications.CHANNEL)
            check(channel.importance == NotificationManager.IMPORTANCE_HIGH && channel.sound != null) { "silent_channel" }
            sendStatus(0, Bundle().apply { putString("stream", "synthetic_call_style_visible\n") })
            Thread.sleep(10000)
            val route = presenter.takeIntent(Intent().putExtra(FamilyCallNotifications.OPEN, callId)
                .putExtra(FamilyCallNotifications.ACTION, "answer"))
            check(route?.get("call_id") == callId && route["action"] == "answer") { "wrong_answer_route" }
            Thread.sleep(200)
            check(active().isEmpty()) { "answer_did_not_cancel" }
            deliver(callId)
            check(active().isEmpty()) { "duplicate_after_answer_rang" }
            val shortCall = "d".repeat(32)
            deliver(shortCall, expiry = System.currentTimeMillis() + 1200)
            Thread.sleep(200)
            check(active().size == 1) { "short_call_not_shown" }
            Thread.sleep(1800)
            check(active().isEmpty()) { "expired_ring_not_cancelled" }
            val endedCall = "e".repeat(32)
            deliver(endedCall, event = "ended")
            deliver(endedCall)
            check(active().isEmpty()) { "out_of_order_push_rang" }
            runOnMainSync { presenter.clear() }
            deliver("f".repeat(32))
            check(active().isEmpty()) { "logout_rang" }
            result.putString("stream", "OK: call_style, sound_channel, expiry, answer_route, dedup, ended, stale_binding, logout\n")
            finish(Activity.RESULT_OK, result)
        } catch (error: Throwable) {
            result.putString("stream", "FAILED: " + (error.message?.takeIf { it.matches(Regex("[a-z_]+")) } ?: error.javaClass.simpleName) + "\n")
            finish(Activity.RESULT_CANCELED, result)
        } finally {
            runOnMainSync { presenter.clear() }
        }
    }
}
