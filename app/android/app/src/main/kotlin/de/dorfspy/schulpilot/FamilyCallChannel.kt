package de.dorfspy.schulpilot

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class FamilyCallChannel(private val activity: MainActivity) {
    private val notifications = FamilyCallNotifications(activity)

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "initialIntent" -> result.success(notifications.takeIntent(activity.intent))
                "bind" -> { notifications.bind(call.argument<String>("binding")); result.success(null) }
                "showIncoming" -> {
                    notifications.show(call.argument<String>("call_id") ?: "",
                        call.argument<Number>("expires_at")?.toLong() ?: 0L)
                    result.success(null)
                }
                "cancel" -> { notifications.cancel(call.argument<String>("call_id") ?: ""); result.success(null) }
                "clear" -> {
                    notifications.clear()
                    FamilyCallCaptureService.stop(activity)
                    result.success(null)
                }
                "status" -> result.success(notifications.status())
                "settings" -> { notifications.openSettings(); result.success(null) }
                "startMedia", "startProjection" -> FamilyCallCaptureService.start(activity,
                    call.argument<String>("call_id") ?: "",
                    call.argument<Boolean>("camera") == true,
                    call.argument<Boolean>("microphone") == true,
                    call.method == "startProjection", result)
                "stopMedia" -> { FamilyCallCaptureService.stop(activity, call.argument<String>("call_id")); result.success(null) }
                else -> result.notImplemented()
            }
        } catch (_: Exception) {
            result.error("CALL_UNAVAILABLE", "Die Android-Anruffunktion ist gerade nicht verfügbar.", null)
        }
    }
}
