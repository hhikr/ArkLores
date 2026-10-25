package com.arklores.arklores

import android.Manifest
import android.app.NotificationManager
import android.app.UiModeManager
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val backgroundChannelName = "arklores/background_work"
    private val themeChannelName = "arklores/app_theme"

    /**
     * The app's own light or dark ("auto": the system's). Android 12+ keeps
     * it and starts the app in it: the system's splash is then the app's
     * paper, not a white screen before a dark app.
     */
    private fun setNightMode(mode: String) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return
        val manager = getSystemService(Context.UI_MODE_SERVICE) as UiModeManager
        manager.setApplicationNightMode(
            when (mode) {
                "yes" -> UiModeManager.MODE_NIGHT_YES
                "no" -> UiModeManager.MODE_NIGHT_NO
                else -> UiModeManager.MODE_NIGHT_AUTO
            },
        )
    }

    override fun onResume() {
        super.onResume()
        requestHighestRefreshRate()
    }

    /**
     * Some systems (ColorOS, OxygenOS) run an app at 60 Hz on a 90/120 Hz
     * screen unless it asks for more; a Flutter app does not ask. Asks for the
     * fastest mode at the current resolution (the system may still lower it,
     * for battery saving or heat).
     */
    private fun requestHighestRefreshRate() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        val display = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            display
        } else {
            @Suppress("DEPRECATION")
            windowManager.defaultDisplay
        } ?: return
        val current = display.mode
        val fastest = display.supportedModes
            .filter {
                it.physicalWidth == current.physicalWidth &&
                    it.physicalHeight == current.physicalHeight
            }
            .maxByOrNull { it.refreshRate } ?: return
        val attributes = window.attributes
        if (attributes.preferredDisplayModeId == fastest.modeId) return
        attributes.preferredDisplayModeId = fastest.modeId
        window.attributes = attributes
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, themeChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "setNightMode" -> {
                    setNightMode(call.argument<String>("mode") ?: "auto")
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, backgroundChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "begin" -> {
                    try {
                        requestNotificationPermissionOnce()
                        BackgroundWorkService.start(
                            applicationContext,
                            call.argument<String>("title") ?: "ArkLores",
                            call.argument<String>("text") ?: "",
                        )
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("start_failed", e.message, null)
                    }
                }
                "end" -> {
                    BackgroundWorkService.stop(applicationContext)
                    result.success(true)
                }
                "access" -> result.success(
                    mapOf(
                        "notifications" to notificationsAllowed(),
                        "batteryExempt" to batteryExempt(),
                    ),
                )
                "requestNotifications" -> {
                    requestNotifications()
                    result.success(true)
                }
                "requestBatteryExempt" -> {
                    requestBatteryExempt()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * Android 13+ shows the foreground service's notification only with this
     * permission (the service runs either way). Asked once, on the first
     * long operation.
     */
    private fun requestNotificationPermissionOnce() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) return
        val prefs = getSharedPreferences("arklores_background", MODE_PRIVATE)
        if (prefs.getBoolean("asked_notifications", false)) return
        prefs.edit().putBoolean("asked_notifications", true).apply()
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 7001)
    }

    private fun notificationsAllowed(): Boolean =
        (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
            .areNotificationsEnabled()

    /**
     * Asks for notifications (Android 13+). Once asked, the system may not
     * show its dialog again: the app's notification settings open instead.
     */
    private fun requestNotifications() {
        if (notificationsAllowed()) return
        val prefs = getSharedPreferences("arklores_background", MODE_PRIVATE)
        val asked = prefs.getBoolean("asked_notifications", false)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && !asked) {
            prefs.edit().putBoolean("asked_notifications", true).apply()
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 7001)
            return
        }
        openSettings(
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName),
        )
    }

    /** Whether the system leaves the app running in the background. */
    private fun batteryExempt(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val power = getSystemService(Context.POWER_SERVICE) as PowerManager
        return power.isIgnoringBatteryOptimizations(packageName)
    }

    /**
     * The system's own dialog for exempting the app from battery
     * optimisation; its settings list where there is no such dialog.
     */
    private fun requestBatteryExempt() {
        if (batteryExempt()) return
        try {
            startActivity(
                Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                    .setData(Uri.parse("package:$packageName")),
            )
        } catch (e: ActivityNotFoundException) {
            openSettings(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
        }
    }

    private fun openSettings(intent: Intent) {
        try {
            startActivity(intent)
        } catch (e: ActivityNotFoundException) {
            startActivity(
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                    .setData(Uri.parse("package:$packageName")),
            )
        }
    }
}
