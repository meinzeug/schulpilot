package de.dorfspy.schulpilot

import android.app.Activity
import android.util.Log
import com.google.android.play.core.appupdate.AppUpdateManagerFactory
import com.google.android.play.core.appupdate.AppUpdateOptions
import com.google.android.play.core.install.model.AppUpdateType
import com.google.android.play.core.install.model.UpdateAvailability

/** Play distribution uses Google's update service, never downloaded APKs. */
class AppUpdater(private val activity: Activity) {
    private val manager = AppUpdateManagerFactory.create(activity)
    private var checking = false
    private var active = false
    fun onStart() {
        active = true
        if (checking) return
        checking = true
        manager.appUpdateInfo.addOnSuccessListener { info ->
            checking = false
            if (active && !activity.isFinishing &&
                (info.updateAvailability() == UpdateAvailability.UPDATE_AVAILABLE ||
                    info.updateAvailability() == UpdateAvailability.DEVELOPER_TRIGGERED_UPDATE_IN_PROGRESS) &&
                info.isUpdateTypeAllowed(AppUpdateType.IMMEDIATE)) {
                try {
                    manager.startUpdateFlowForResult(info, activity, AppUpdateOptions.newBuilder(AppUpdateType.IMMEDIATE).build(), 4210)
                } catch (_: Exception) { Log.w("SchulpilotUpdate", "Play update could not start") }
            }
        }.addOnFailureListener {
            checking = false
            Log.i("SchulpilotUpdate", "Play update service is not available")
        }
    }
    fun onStop() { active = false }
    fun close() { active = false }
}
