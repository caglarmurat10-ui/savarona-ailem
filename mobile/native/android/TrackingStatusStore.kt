package com.savarona.ailem

import android.content.Context

object TrackingStatusStore {
    private const val PREFS = "savarona_tracking_status"
    private const val KEY_PERMISSION_STATE = "permissionState"
    private const val KEY_TRACKING_ACTIVE = "trackingActive"
    private const val KEY_TRACKING_REQUESTED = "trackingRequested"
    private const val KEY_FOREGROUND_RUNNING = "foregroundServiceRunning"
    private const val KEY_LAST_SEND_ATTEMPT = "lastSendAttemptAt"
    private const val KEY_LAST_SEND_SUCCESS = "lastSendSuccessAt"
    private const val KEY_LAST_ERROR = "lastError"
    private const val KEY_API_BASE_URL = "apiBaseUrl"
    private const val KEY_SEQUENCE = "sequenceCounter"
    private fun prefs(context: Context) = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun setPermissionState(context: Context, state: String) = prefs(context).edit().putString(KEY_PERMISSION_STATE, state).apply()
    fun permissionState(context: Context): String = prefs(context).getString(KEY_PERMISSION_STATE, "not_requested") ?: "not_requested"
    fun setTrackingActive(context: Context, active: Boolean) = prefs(context).edit().putBoolean(KEY_TRACKING_ACTIVE, active).apply()
    fun setTrackingRequested(context: Context, requested: Boolean) = prefs(context).edit().putBoolean(KEY_TRACKING_REQUESTED, requested).apply()
    fun isTrackingRequested(context: Context): Boolean = prefs(context).getBoolean(KEY_TRACKING_REQUESTED, false)
    fun setForegroundRunning(context: Context, running: Boolean) = prefs(context).edit().putBoolean(KEY_FOREGROUND_RUNNING, running).apply()
    fun markSendAttempt(context: Context) = prefs(context).edit().putLong(KEY_LAST_SEND_ATTEMPT, System.currentTimeMillis()).apply()
    fun markSendSuccess(context: Context) = prefs(context).edit().putLong(KEY_LAST_SEND_SUCCESS, System.currentTimeMillis()).remove(KEY_LAST_ERROR).apply()
    fun setLastError(context: Context, message: String?) = prefs(context).edit().putString(KEY_LAST_ERROR, message).apply()

    fun saveCredentials(context: Context, apiBaseUrl: String, deviceToken: String) {
        prefs(context).edit().putString(KEY_API_BASE_URL, apiBaseUrl).apply()
        SecureCredentialStore.saveDeviceToken(context, deviceToken)
    }
    fun apiBaseUrl(context: Context): String? = prefs(context).getString(KEY_API_BASE_URL, null)
    fun deviceToken(context: Context): String? = SecureCredentialStore.readDeviceToken(context)

    @Synchronized
    fun nextSequenceNo(context: Context): Long {
        val p = prefs(context)
        val next = p.getLong(KEY_SEQUENCE, 0L) + 1
        p.edit().putLong(KEY_SEQUENCE, next).commit()
        return next
    }

    fun clearCredentials(context: Context) {
        prefs(context).edit().remove(KEY_API_BASE_URL).apply()
        SecureCredentialStore.clear(context)
    }

    fun snapshot(context: Context, queuedCount: Int): Map<String, Any?> {
        val p = prefs(context)
        return mapOf(
            "permissionState" to permissionState(context),
            "trackingActive" to p.getBoolean(KEY_TRACKING_ACTIVE, false),
            "trackingRequested" to p.getBoolean(KEY_TRACKING_REQUESTED, false),
            "foregroundServiceRunning" to p.getBoolean(KEY_FOREGROUND_RUNNING, false),
            "queuedCount" to queuedCount,
            "lastSendAttemptAt" to p.getLong(KEY_LAST_SEND_ATTEMPT, -1L).let { if (it < 0) null else it },
            "lastSendSuccessAt" to p.getLong(KEY_LAST_SEND_SUCCESS, -1L).let { if (it < 0) null else it },
            "lastError" to p.getString(KEY_LAST_ERROR, null),
        )
    }
}
