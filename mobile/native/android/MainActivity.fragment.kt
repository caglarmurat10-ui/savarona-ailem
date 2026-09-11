package com.savarona.ailem

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.annotation.NonNull
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest

class MainActivity : FlutterActivity() {
    private val trackingChannelName = "savarona_ailem/tracking"
    private val updaterChannelName = "savarona_ailem/updater"
    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, trackingChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "status" -> {
                    refreshPermissionState()
                    val queued = LocationTrackingService.queuedCount(applicationContext)
                    result.success(TrackingStatusStore.snapshot(applicationContext, queued))
                }
                "requestPermissions" -> {
                    pendingPermissionResult = result
                    requestLocationPermissions()
                }
                "openAppSettings" -> {
                    startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply { data = Uri.parse("package:$packageName") })
                    result.success(null)
                }
                "start" -> {
                    val apiBaseUrl = call.argument<String>("apiBaseUrl")
                    val deviceToken = call.argument<String>("deviceToken")
                    if (apiBaseUrl == null || deviceToken == null) {
                        result.error("invalid_args", "apiBaseUrl/deviceToken required", null)
                    } else {
                        TrackingStatusStore.setTrackingRequested(applicationContext, true)
                        TrackingStatusStore.saveCredentials(applicationContext, apiBaseUrl, deviceToken)
                        ContextCompat.startForegroundService(this, Intent(this, LocationTrackingService::class.java))
                        result.success(null)
                    }
                }
                "stop" -> {
                    TrackingStatusStore.setTrackingRequested(applicationContext, false)
                    stopService(Intent(this, LocationTrackingService::class.java))
                    TrackingStatusStore.setTrackingActive(applicationContext, false)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, updaterChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "downloadAndInstall" -> {
                    val url = call.argument<String>("url")
                    val expectedSha256 = call.argument<String>("sha256")?.lowercase()
                    val versionCode = call.argument<Number>("versionCode")?.toLong()
                    if (url.isNullOrBlank() || expectedSha256 == null || expectedSha256.length != 64 || versionCode == null) {
                        result.error("invalid_args", "url/sha256/versionCode required", null)
                    } else {
                        downloadAndInstall(url, expectedSha256, versionCode, result)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun downloadAndInstall(url: String, expectedSha256: String, versionCode: Long, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !packageManager.canRequestPackageInstalls()) {
            startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName")))
            result.success("permission_required")
            return
        }

        Thread {
            try {
                val updatesDir = File(cacheDir, "updates").apply { mkdirs() }
                val apk = File(updatesDir, "savarona-ailem-$versionCode.apk")
                val digest = MessageDigest.getInstance("SHA-256")
                val conn = URL(url).openConnection() as HttpURLConnection
                conn.instanceFollowRedirects = true
                conn.connectTimeout = 15_000
                conn.readTimeout = 30_000
                conn.setRequestProperty("User-Agent", "Savarona-Ailem-Updater/1")
                conn.connect()
                if (conn.responseCode !in 200..299) throw IllegalStateException("http_${conn.responseCode}")
                conn.inputStream.use { input ->
                    FileOutputStream(apk).use { output ->
                        val buffer = ByteArray(64 * 1024)
                        while (true) {
                            val n = input.read(buffer)
                            if (n <= 0) break
                            digest.update(buffer, 0, n)
                            output.write(buffer, 0, n)
                        }
                    }
                }
                conn.disconnect()
                val actual = digest.digest().joinToString("") { "%02x".format(it) }
                if (!actual.equals(expectedSha256, ignoreCase = true)) {
                    apk.delete()
                    throw SecurityException("sha256_mismatch")
                }
                runOnUiThread {
                    try {
                        val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", apk)
                        val intent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, "application/vnd.android.package-archive")
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(intent)
                        result.success("install_started")
                    } catch (e: Exception) {
                        result.error("install_failed", e.javaClass.simpleName, null)
                    }
                }
            } catch (e: Exception) {
                runOnUiThread { result.error("update_failed", e.message ?: e.javaClass.simpleName, null) }
            }
        }.start()
    }

    override fun onResume() {
        super.onResume()
        refreshPermissionState()
        if (TrackingStatusStore.isTrackingRequested(applicationContext) && hasAnyLocationPermission()) {
            val hasBg = Build.VERSION.SDK_INT < Build.VERSION_CODES.Q ||
                ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_BACKGROUND_LOCATION) == PackageManager.PERMISSION_GRANTED
            if (hasBg && TrackingStatusStore.apiBaseUrl(applicationContext) != null && TrackingStatusStore.deviceToken(applicationContext) != null) {
                ContextCompat.startForegroundService(this, Intent(this, LocationTrackingService::class.java))
            }
        }
    }

    private fun hasAnyLocationPermission(): Boolean =
        ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED ||
            ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED

    private fun refreshPermissionState() {
        val any = hasAnyLocationPermission()
        val always = Build.VERSION.SDK_INT < Build.VERSION_CODES.Q ||
            ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_BACKGROUND_LOCATION) == PackageManager.PERMISSION_GRANTED
        val wasRequested = TrackingStatusStore.isTrackingRequested(applicationContext)
        TrackingStatusStore.setPermissionState(applicationContext, when {
            !any && wasRequested -> "permission_lost"
            !any -> "denied"
            always -> "granted_always"
            else -> "granted_when_in_use"
        })
    }

    private fun requestLocationPermissions() {
        if (!hasAnyLocationPermission()) {
            ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION), REQUEST_FOREGROUND_LOCATION)
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val bgGranted = ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_BACKGROUND_LOCATION) == PackageManager.PERMISSION_GRANTED
            if (!bgGranted) {
                ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.ACCESS_BACKGROUND_LOCATION), REQUEST_BACKGROUND_LOCATION)
                return
            }
        }
        requestNotificationPermissionThenFinish()
    }

    private fun requestNotificationPermissionThenFinish() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQUEST_NOTIFICATIONS)
            return
        }
        finishPermissionRequest(true)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        val anyGranted = grantResults.any { it == PackageManager.PERMISSION_GRANTED }
        when (requestCode) {
            REQUEST_FOREGROUND_LOCATION -> if (anyGranted) requestLocationPermissions() else finishPermissionRequest(false)
            REQUEST_BACKGROUND_LOCATION -> if (anyGranted) requestNotificationPermissionThenFinish() else finishPermissionRequest(false)
            REQUEST_NOTIFICATIONS -> finishPermissionRequest(hasAnyLocationPermission() && (
                Build.VERSION.SDK_INT < Build.VERSION_CODES.Q ||
                    ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_BACKGROUND_LOCATION) == PackageManager.PERMISSION_GRANTED
            ))
        }
    }

    private fun finishPermissionRequest(granted: Boolean) {
        refreshPermissionState()
        pendingPermissionResult?.success(granted)
        pendingPermissionResult = null
    }

    companion object {
        private const val REQUEST_FOREGROUND_LOCATION = 4201
        private const val REQUEST_BACKGROUND_LOCATION = 4202
        private const val REQUEST_NOTIFICATIONS = 4203
    }
}
