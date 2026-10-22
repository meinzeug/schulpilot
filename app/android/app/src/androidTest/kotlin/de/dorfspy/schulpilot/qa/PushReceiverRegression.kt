package de.dorfspy.schulpilot.qa

import android.app.Activity
import android.app.Instrumentation
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import de.dorfspy.schulpilot.FamilyCallMessagingReceiver
import io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingStore
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** No Firebase network, account, token or private content; never in release APKs. */
class PushReceiverRegression(private val instrumentation: Instrumentation) {
    fun run() {
        val context = instrumentation.targetContext
        val messageId = "schulpilot-native-push-regression"
        val storedBeforeCompletion = CountDownLatch(1)
        val result = Bundle()
        try {
            instrumentation.startActivitySync(Intent().setClassName(context,
                "de.dorfspy.schulpilot.MainActivity").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            instrumentation.waitForIdleSync()
            // Android, not a direct onReceive invocation, must attach PendingResult.
            // A manually constructed delegate loses that result and crashes in finish().
            context.sendOrderedBroadcast(Intent("com.google.android.c2dm.intent.RECEIVE")
                .setClass(context, FamilyCallMessagingReceiver::class.java)
                .putExtra("google.message_id", messageId)
                .putExtra("gcm.n.e", "1")
                .putExtra("gcm.n.title", "SCHULPILOT")
                .putExtra("gcm.n.body", "Es gibt Neuigkeiten in SCHULPILOT.")
                .putExtra("route", "/app"), null, object : BroadcastReceiver() {
                    override fun onReceive(context: Context, intent: Intent) {
                        if (FlutterFirebaseMessagingStore.getInstance()
                                .getFirebaseMessageMap(messageId) != null) {
                            storedBeforeCompletion.countDown()
                        }
                    }
                }, Handler(Looper.getMainLooper()), Activity.RESULT_OK, null, null)
            check(storedBeforeCompletion.await(5, TimeUnit.SECONDS)) { "pending_result_ended_before_store" }
            val stored = FlutterFirebaseMessagingStore.getInstance()
                .getFirebaseMessageMap(messageId)?.get("message") as? Map<*, *>
            check((stored?.get("data") as? Map<*, *>)?.get("route") == "/app") { "stored_route_missing" }
            check((stored?.get("notification") as? Map<*, *>)?.get("title") == "SCHULPILOT") { "stored_title_missing" }
            // The old delegated receiver threw on its executor after publishing LiveData.
            Thread.sleep(1000)
            instrumentation.waitForIdleSync()
            result.putString("stream", "OK: framework_pending_result, stored_before_finish, route_and_title, process_alive\n")
            instrumentation.finish(Activity.RESULT_OK, result)
        } catch (error: Throwable) {
            result.putString("stream", "FAILED: " +
                (error.message?.takeIf { it.matches(Regex("[a-z_]+")) } ?: error.javaClass.simpleName) + "\n")
            instrumentation.finish(Activity.RESULT_CANCELED, result)
        } finally {
            FlutterFirebaseMessagingStore.getInstance().removeFirebaseMessage(messageId)
        }
    }
}
