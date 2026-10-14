package de.dorfspy.schulpilot

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.SystemClock
import android.provider.Settings
import android.util.Log
import android.widget.ProgressBar
import android.widget.Toast
import androidx.core.content.FileProvider
import org.json.JSONObject
import java.io.File
import java.net.URL
import java.security.MessageDigest
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import javax.net.ssl.HttpsURLConnection

/** Direct APK distribution only. The Play flavor contains no APK installer. */
class AppUpdater(private val activity: Activity) {
    private val executor = Executors.newSingleThreadExecutor()
    private val busy = AtomicBoolean(false)
    private val cancelled = AtomicBoolean(false)
    private var active = false
    private var dialog: AlertDialog? = null
    private var attemptedVersion: Long? = null
    private val directory get() = File(activity.cacheDir, "updates").apply { mkdirs() }

    data class Release(val code: Long, val version: String, val size: Long, val sha: String, val url: String)

    fun onStart() {
        active = true
        // No persisted "last checked" time, no daily interval, no account data.
        Log.i("SchulpilotUpdate", "Checking release manifest on app start")
        if (!busy.compareAndSet(false, true)) return
        cancelled.set(false)
        executor.execute {
            try {
                val connection = connect("https://schulpilot.dorfspy.de/api/app-release?check=${System.currentTimeMillis()}")
                val manifest = try {
                    connection.inputStream.use { input ->
                        val bytes = ByteArray(16385)
                        var total = 0
                        while (total < bytes.size) {
                            val count = input.read(bytes, total, bytes.size - total)
                            if (count < 0) break
                            total += count
                        }
                        require(total <= 16384)
                        JSONObject(String(bytes, 0, total, Charsets.UTF_8))
                    }
                } finally { connection.disconnect() }
                val installed = installedInfo()
                if (!manifest.optBoolean("available")) return@execute
                require(manifest.getString("application_id") == activity.packageName)
                require(manifest.getString("channel") == "stable")
                val release = Release(
                    manifest.getLong("version_code"), manifest.getString("version").take(60),
                    manifest.getLong("size_bytes"), manifest.getString("sha256"), manifest.getString("download_url")
                )
                require(release.size in 1..150L * 1024 * 1024 && release.sha.matches(Regex("[a-f0-9]{64}")))
                val uri = Uri.parse(release.url)
                require(uri.scheme == "https" && uri.host == "schulpilot.dorfspy.de" && uri.port == -1 &&
                    uri.userInfo == null && uri.path == "/downloads/schulpilot-android.apk" && uri.fragment == null)
                if (release.code <= versionCode(installed)) {
                    directory.listFiles()?.forEach { it.delete() }
                    Log.i("SchulpilotUpdate", "Installed version is current")
                    return@execute
                }
                val target = File(directory, "update-${release.code}.apk")
                directory.listFiles()?.filter { it != target }?.forEach { it.delete() }
                if (!target.isFile || !verify(target, release, installed)) {
                    target.delete()
                    var progress: ProgressBar? = null
                    ui {
                        progress = ProgressBar(activity, null, android.R.attr.progressBarStyleHorizontal).apply { max = 100 }
                        dialog?.dismiss()
                        dialog = AlertDialog.Builder(activity).setTitle("SCHULPILOT wird aktualisiert")
                            .setMessage("Version ${release.version} wird sicher geladen. Deine Lerndaten bleiben erhalten. Android bestätigt anschließend die Installation.")
                            .setView(progress).setNegativeButton("Später") { _, _ -> cancelled.set(true) }
                            .setOnCancelListener { cancelled.set(true) }.show()
                    }
                    val partial = File(directory, "download.part")
                    try {
                        val download = connect(release.url)
                        try {
                            download.inputStream.use { input ->
                                partial.outputStream().use { output ->
                                    val buffer = ByteArray(64 * 1024)
                                    var total = 0L
                                    var lastProgress = -1
                                    val deadline = SystemClock.elapsedRealtime() + 180000
                                    while (true) {
                                        if (cancelled.get() || Thread.currentThread().isInterrupted) throw InterruptedException()
                                        require(SystemClock.elapsedRealtime() < deadline)
                                        val count = input.read(buffer)
                                        if (count < 0) break
                                        total += count
                                        require(total <= release.size)
                                        output.write(buffer, 0, count)
                                        val percent = (total * 100 / release.size).toInt()
                                        if (percent != lastProgress) { lastProgress = percent; ui { progress?.progress = percent } }
                                    }
                                    require(total == release.size)
                                }
                            }
                        } finally { download.disconnect() }
                        require(verify(partial, release, installed))
                        require(partial.renameTo(target))
                    } finally { partial.delete() }
                }
                Log.i("SchulpilotUpdate", "New APK verified: size, SHA-256, package, version and signing certificate")
                ui {
                    dialog?.dismiss()
                    if (attemptedVersion == release.code) {
                        dialog = AlertDialog.Builder(activity).setTitle("Update ist bereit")
                            .setMessage("Android hat die Installation noch nicht abgeschlossen. Du kannst weiterlernen oder Version ${release.version} jetzt installieren.")
                            .setPositiveButton("Installieren") { _, _ -> install(target, release) }
                            .setNegativeButton("Später", null).show()
                    } else install(target, release)
                }
            } catch (_: InterruptedException) {
                Log.i("SchulpilotUpdate", "Update download deferred")
            } catch (_: Exception) {
                // Never log URLs, response bodies, tokens or account information.
                Log.w("SchulpilotUpdate", "Update check or verification failed; learning remains available")
                ui {
                    dialog?.dismiss()
                    Toast.makeText(activity, "Update derzeit nicht möglich. Beim nächsten Öffnen wird erneut geprüft. Du kannst weiterlernen.", Toast.LENGTH_LONG).show()
                }
            } finally { busy.set(false) }
        }
    }

    private fun install(file: File, release: Release) {
        if (Build.VERSION.SDK_INT >= 26 && !activity.packageManager.canRequestPackageInstalls()) {
            dialog = AlertDialog.Builder(activity).setTitle("Update-Installation erlauben")
                .setMessage("Erlaube Android einmalig, Updates aus SCHULPILOT zu installieren. Anschließend bestätigst du das Update. Andere Apps werden nicht installiert.")
                .setPositiveButton("Android-Einstellungen öffnen") { _, _ ->
                    try {
                        activity.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${activity.packageName}")))
                    } catch (_: Exception) { failure() }
                }.setNegativeButton("Später", null).show()
            return
        }
        try {
            // Revalidate the private file immediately before handing it to Android.
            require(verify(file, release, installedInfo()))
            val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.updates", file)
            attemptedVersion = release.code
            activity.startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/vnd.android.package-archive")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))
        } catch (_: Exception) { failure() }
    }

    private fun failure() { Toast.makeText(activity, "Android konnte das geprüfte Update nicht öffnen. Bitte später erneut versuchen.", Toast.LENGTH_LONG).show() }

    @Suppress("DEPRECATION")
    private fun installedInfo(): PackageInfo = activity.packageManager.getPackageInfo(activity.packageName, signatureFlags())

    @Suppress("DEPRECATION")
    private fun signatureFlags() = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES

    @Suppress("DEPRECATION")
    private fun versionCode(info: PackageInfo): Long = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()

    @Suppress("DEPRECATION")
    private fun signers(info: PackageInfo): Set<String> =
        (if (Build.VERSION.SDK_INT >= 28) info.signingInfo?.apkContentsSigners else info.signatures)
            ?.map { signature -> MessageDigest.getInstance("SHA-256").digest(signature.toByteArray()).joinToString("") { "%02x".format(it) } }
            ?.toSet() ?: emptySet()

    @Suppress("DEPRECATION")
    private fun verify(file: File, release: Release, installed: PackageInfo): Boolean {
        if (file.length() != release.size) return false
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(64 * 1024)
            while (true) { val count = input.read(buffer); if (count < 0) break; digest.update(buffer, 0, count) }
        }
        if (digest.digest().joinToString("") { "%02x".format(it) } != release.sha) return false
        val archive = activity.packageManager.getPackageArchiveInfo(file.path, signatureFlags()) ?: return false
        val expected = signers(installed)
        return archive.packageName == activity.packageName && versionCode(archive) == release.code &&
            versionCode(archive) > versionCode(installed) && expected.isNotEmpty() && signers(archive) == expected &&
            (archive.applicationInfo?.minSdkVersion ?: Int.MAX_VALUE) <= Build.VERSION.SDK_INT
    }

    private fun connect(url: String): HttpsURLConnection {
        val connection = URL(url).openConnection() as HttpsURLConnection
        connection.instanceFollowRedirects = false
        connection.connectTimeout = 10000
        connection.readTimeout = 30000
        connection.useCaches = false
        connection.setRequestProperty("Cache-Control", "no-cache, no-store")
        connection.setRequestProperty("Accept-Encoding", "identity")
        try { require(connection.responseCode == 200) } catch (error: Exception) { connection.disconnect(); throw error }
        return connection
    }

    private fun ui(block: () -> Unit) { activity.runOnUiThread { if (active && !activity.isFinishing && !activity.isDestroyed) block() } }
    fun onStop() { active = false }
    fun close() { active = false; cancelled.set(true); dialog?.dismiss(); executor.shutdownNow() }
}
