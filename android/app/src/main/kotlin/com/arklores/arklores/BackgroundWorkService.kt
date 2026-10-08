package com.arklores.arklores

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
import android.os.PowerManager

/**
 * Foreground service that keeps the process (and its network sockets) alive
 * while a long operation runs (an Ask answer, a download, ...). It does no
 * work itself: the Dart side starts it when the first operation begins,
 * updates its text, and stops it when the last one ends.
 */
class BackgroundWorkService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val title = intent?.getStringExtra(EXTRA_TITLE) ?: "ArkLores"
        val text = intent?.getStringExtra(EXTRA_TEXT) ?: ""
        val notification = buildNotification(title, text)
        instance = this
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        if (wakeLock == null) {
            val power = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = power.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "ArkLores:background-work").apply {
                setReferenceCounted(false)
                // A safety net: no operation of the app runs this long.
                acquire(WAKE_LOCK_TIMEOUT_MS)
            }
        }
        // If the system kills the process, the operation died with it.
        return START_NOT_STICKY
    }

    /**
     * The user swiped the app away: the Flutter engine (and the operation in
     * it) is gone with the activity, so the notification and the wake lock
     * must not stay behind.
     */
    override fun onTaskRemoved(rootIntent: Intent?) {
        stopSelf()
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        if (instance === this) instance = null
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        super.onDestroy()
    }

    /** New text on the running service's notification. */
    private fun update(title: String, text: String) {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(NOTIFICATION_ID, buildNotification(title, text))
    }

    private fun buildNotification(title: String, text: String): Notification {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val builder: Notification.Builder
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            if (manager.getNotificationChannel(CHANNEL_ID) == null) {
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    "ArkLores background work",
                    NotificationManager.IMPORTANCE_LOW,
                )
                channel.setShowBadge(false)
                manager.createNotificationChannel(channel)
            }
            builder = Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            builder = Notification.Builder(this)
        }
        val open = packageManager.getLaunchIntentForPackage(packageName)
        if (open != null) {
            builder.setContentIntent(
                PendingIntent.getActivity(this, 0, open, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT),
            )
        }
        return builder
            .setSmallIcon(android.R.drawable.stat_notify_sync)
            .setContentTitle(title)
            .setContentText(text)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .build()
    }

    companion object {
        private const val CHANNEL_ID = "arklores_background_work"
        private const val NOTIFICATION_ID = 7001
        private const val WAKE_LOCK_TIMEOUT_MS = 3L * 60 * 60 * 1000
        const val EXTRA_TITLE = "title"
        const val EXTRA_TEXT = "text"

        /** The running service, if any (main thread only). */
        private var instance: BackgroundWorkService? = null

        /**
         * Starts the service, or updates its notification when it runs. An
         * update does not start the service again: from the background,
         * Android 12+ may refuse a foreground-service start.
         */
        fun start(context: Context, title: String, text: String) {
            instance?.let {
                it.update(title, text)
                return
            }
            val intent = Intent(context, BackgroundWorkService::class.java)
                .putExtra(EXTRA_TITLE, title)
                .putExtra(EXTRA_TEXT, text)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            // A start right after this must start a new service, not update
            // the one that is stopping.
            instance = null
            context.stopService(Intent(context, BackgroundWorkService::class.java))
        }
    }
}
