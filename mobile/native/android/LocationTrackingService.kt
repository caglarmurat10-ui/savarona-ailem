// Template: merge into the generated Flutter Android app.
// Package name should match the final Android applicationId.
// Requires (add to app/build.gradle.kts):
//   implementation("com.google.android.gms:play-services-location:21.3.0")
package com.savarona.ailem

import android.Manifest
import android.app.*
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.BatteryManager
import android.os.IBinder
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import com.google.android.gms.location.*
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import javax.net.ssl.HttpsURLConnection

private enum class SpeedProfile(val intervalMs: Long, val minUpdateIntervalMs: Long, val minDistanceM: Float) {
    VEHICLE(4_000L, 3_000L, 15f),
    WALKING(11_000L, 8_000L, 10f),
    STATIONARY(60_000L, 30_000L, 0f),
}

class LocationTrackingService : Service() {
    private lateinit var fused: FusedLocationProviderClient
    private lateinit var callback: LocationCallback
    private lateinit var queue: TrackingUploadQueue
    private var currentProfile: SpeedProfile? = null
    private var flushThread: Thread? = null
    @Volatile private var running = false
    private var lastHeartbeatAt = 0L

    override fun onCreate() {
        super.onCreate()
        fused = LocationServices.getFusedLocationProviderClient(this)
        queue = TrackingUploadQueue(this)
        ensureChannel()
        callback = object : LocationCallback() {
            override fun onLocationResult(result: LocationResult) {
                val location = result.lastLocation ?: return
                onNewLocation(location)
            }
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val apiBaseUrl = intent?.getStringExtra(EXTRA_API_BASE_URL) ?: TrackingStatusStore.apiBaseUrl(this)
        val deviceToken = intent?.getStringExtra(EXTRA_DEVICE_TOKEN) ?: TrackingStatusStore.deviceToken(this)
        if (apiBaseUrl == null || deviceToken == null) {
            stopSelf()
            return START_NOT_STICKY
        }
        TrackingStatusStore.saveCredentials(this, apiBaseUrl, deviceToken)
        TrackingStatusStore.setTrackingRequested(this, true)

        startForeground(NOTIFICATION_ID, buildNotification("Canlı konum paylaşımı aktif"))
        TrackingStatusStore.setForegroundRunning(this, true)

        if (!hasLocationPermission()) {
            TrackingStatusStore.setPermissionState(this, "permission_lost")
            TrackingStatusStore.setTrackingActive(this, false)
            updateNotification("Konum izni yok — paylaşım duraklatıldı")
            return START_NOT_STICKY
        }
        TrackingStatusStore.setPermissionState(this, if (hasBackgroundPermission()) "granted_always" else "granted_when_in_use")

        requestUpdates(SpeedProfile.WALKING)
        TrackingStatusStore.setTrackingActive(this, true)
        startFlushLoop()
        return START_STICKY
    }

    @Suppress("MissingPermission")
    private fun requestUpdates(profile: SpeedProfile) {
        if (currentProfile == profile) return
        if (!hasLocationPermission()) return
        currentProfile = profile
        val request = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, profile.intervalMs)
            .setMinUpdateIntervalMillis(profile.minUpdateIntervalMs)
            .setMinUpdateDistanceMeters(profile.minDistanceM)
            .build()
        fused.removeLocationUpdates(callback)
        fused.requestLocationUpdates(request, callback, mainLooper)
    }

    private fun onNewLocation(location: android.location.Location) {
        val lat = location.latitude
        val lng = location.longitude
        if (!lat.isFinite() || !lng.isFinite() || lat !in -90.0..90.0 || lng !in -180.0..180.0) return
        val speed = if (location.hasSpeed()) location.speed.toDouble().takeIf { it.isFinite() && it >= 0.0 } else null
        val profile = when {
            speed != null && speed >= 8.0 -> SpeedProfile.VEHICLE
            speed != null && speed >= 0.5 -> SpeedProfile.WALKING
            else -> SpeedProfile.STATIONARY
        }
        requestUpdates(profile)

        val sample = LocationSample(
            sequenceNo = TrackingStatusStore.nextSequenceNo(this),
            capturedAt = location.time,
            lat = lat,
            lng = lng,
            accuracyM = if (location.hasAccuracy()) location.accuracy.toDouble().takeIf { it.isFinite() && it >= 0.0 } else null,
            speedMps = speed,
            headingDeg = if (location.hasBearing()) location.bearing.toDouble().takeIf { it.isFinite() } else null,
            batteryPct = currentBatteryPct(),
            activity = when (profile) {
                SpeedProfile.VEHICLE -> "automotive"
                SpeedProfile.WALKING -> "walking"
                SpeedProfile.STATIONARY -> "stationary"
            },
        )
        queue.enqueue(sample)
    }

    private fun currentBatteryPct(): Int? {
        val bm = getSystemService(Context.BATTERY_SERVICE) as? BatteryManager ?: return null
        val pct = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
        return if (pct in 0..100) pct else null
    }

    private fun startFlushLoop() {
        if (flushThread?.isAlive == true) return
        running = true
        flushThread = Thread {
            var backoffMs = 2_000L
            while (running) {
                val nowMs = System.currentTimeMillis()
                if (nowMs - lastHeartbeatAt >= HEARTBEAT_INTERVAL_MS) {
                    sendHeartbeat()
                    lastHeartbeatAt = nowMs
                }
                if (!hasLocationPermission()) {
                    TrackingStatusStore.setPermissionState(this, "permission_lost")
                    TrackingStatusStore.setTrackingActive(this, false)
                    fused.removeLocationUpdates(callback)
                    currentProfile = null
                    updateNotification("Konum izni kapatıldı — paylaşım duraklatıldı")
                    Thread.sleep(10_000L)
                    continue
                } else if (currentProfile == null) {
                    TrackingStatusStore.setPermissionState(this, if (hasBackgroundPermission()) "granted_always" else "granted_when_in_use")
                    requestUpdates(SpeedProfile.WALKING)
                    TrackingStatusStore.setTrackingActive(this, true)
                    updateNotification("Canlı konum paylaşımı aktif")
                }
                val item = queue.peekOldest()
                if (item == null) {
                    Thread.sleep(2_000L)
                    continue
                }
                TrackingStatusStore.markSendAttempt(this)
                val outcome = sendSample(item)
                when (outcome) {
                    is SendOutcome.Delivered, is SendOutcome.AlreadyDelivered -> {
                        queue.remove(item.rowId)
                        TrackingStatusStore.markSendSuccess(this)
                        backoffMs = 2_000L
                    }
                    is SendOutcome.Failed -> {
                        TrackingStatusStore.setLastError(this, outcome.message)
                        Thread.sleep(backoffMs)
                        backoffMs = (backoffMs * 2).coerceAtMost(60_000L)
                    }
                }
            }
        }.apply { isDaemon = true; start() }
    }

    private sealed class SendOutcome {
        object Delivered : SendOutcome()
        object AlreadyDelivered : SendOutcome()
        data class Failed(val message: String) : SendOutcome()
    }

    private fun sendSample(item: QueuedSample): SendOutcome {
        if (!item.isUsable()) return SendOutcome.AlreadyDelivered
        val apiBaseUrl = TrackingStatusStore.apiBaseUrl(this) ?: return SendOutcome.Failed("missing_api_base_url")
        val deviceToken = TrackingStatusStore.deviceToken(this) ?: return SendOutcome.Failed("missing_device_token")
        return try {
            val url = URL("${apiBaseUrl.trimEnd('/')}/v1/location")
            val conn = (url.openConnection() as? HttpsURLConnection ?: url.openConnection() as HttpURLConnection)
            conn.requestMethod = "POST"
            conn.doOutput = true
            conn.connectTimeout = 10_000
            conn.readTimeout = 10_000
            conn.setRequestProperty("Content-Type", "application/json")
            conn.setRequestProperty("Authorization", "Bearer $deviceToken")
            OutputStreamWriter(conn.outputStream).use { it.write(item.toJson()) }
            when (conn.responseCode) {
                200 -> SendOutcome.Delivered
                409 -> SendOutcome.AlreadyDelivered
                else -> SendOutcome.Failed("http_${conn.responseCode}")
            }
        } catch (e: Exception) {
            SendOutcome.Failed(e.javaClass.simpleName)
        }
    }

    private fun sendHeartbeat() {
        val apiBaseUrl = TrackingStatusStore.apiBaseUrl(this) ?: return
        val deviceToken = TrackingStatusStore.deviceToken(this) ?: return
        val permission = if (!hasLocationPermission()) "permission_lost" else if (hasBackgroundPermission()) "granted_always" else "granted_when_in_use"
        val appState = if (hasLocationPermission()) "tracking" else "permission_lost"
        try {
            val url = URL("${apiBaseUrl.trimEnd('/')}/v1/heartbeat")
            val conn = (url.openConnection() as? HttpsURLConnection ?: url.openConnection() as HttpURLConnection)
            conn.requestMethod = "POST"
            conn.doOutput = true
            conn.connectTimeout = 8_000
            conn.readTimeout = 8_000
            conn.setRequestProperty("Content-Type", "application/json")
            conn.setRequestProperty("Authorization", "Bearer $deviceToken")
            val battery = currentBatteryPct()?.toString() ?: "null"
            val json = "{\"battery_pct\":$battery,\"permission_state\":\"$permission\",\"app_state\":\"$appState\"}"
            OutputStreamWriter(conn.outputStream).use { it.write(json) }
            conn.responseCode
            conn.disconnect()
        } catch (_: Exception) {
        }
    }

    private fun hasLocationPermission(): Boolean =
        ActivityCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED ||
        ActivityCompat.checkSelfPermission(this, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED

    private fun hasBackgroundPermission(): Boolean =
        android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.Q ||
        ActivityCompat.checkSelfPermission(this, Manifest.permission.ACCESS_BACKGROUND_LOCATION) == PackageManager.PERMISSION_GRANTED

    override fun onDestroy() {
        running = false
        fused.removeLocationUpdates(callback)
        TrackingStatusStore.setTrackingActive(this, false)
        TrackingStatusStore.setForegroundRunning(this, false)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun ensureChannel() {
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel(
            CHANNEL_ID, "Konum paylaşımı", NotificationManager.IMPORTANCE_LOW
        ))
    }

    private fun buildNotification(text: String): Notification =
        NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setContentTitle("Savarona Ailem")
            .setContentText(text)
            .setOngoing(true)
            .build()

    private fun updateNotification(text: String) {
        val nm = getSystemService(NotificationManager::class.java)
        nm.notify(NOTIFICATION_ID, buildNotification(text))
    }

    companion object {
        const val CHANNEL_ID = "savarona_tracking"
        const val NOTIFICATION_ID = 4107
        const val EXTRA_API_BASE_URL = "apiBaseUrl"
        const val EXTRA_DEVICE_TOKEN = "deviceToken"
        const val HEARTBEAT_INTERVAL_MS = 30_000L

        fun queuedCount(context: Context): Int = TrackingUploadQueue(context).count()
    }
}
