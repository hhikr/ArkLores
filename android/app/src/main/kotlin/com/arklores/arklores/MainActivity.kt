package com.arklores.arklores

import android.Manifest
import android.content.ComponentName
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val channelName = "arklores/app_icon"
    private val backgroundChannelName = "arklores/background_work"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "setIcon" -> {
                    val icon = call.argument<String>("icon")
                    if (icon == "light" || icon == "dark") {
                        setLauncherIcon(icon)
                        result.success(true)
                    } else {
                        result.error("invalid_icon", "Unknown launcher icon: $icon", null)
                    }
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

    private fun setLauncherIcon(icon: String) {
        val lightAlias = ComponentName(packageName, "$packageName.MainActivityLightAlias")
        val darkAlias = ComponentName(packageName, "$packageName.MainActivityDarkAlias")
        packageManager.setComponentEnabledSetting(
            lightAlias,
            if (icon == "light") {
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED
            } else {
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED
            },
            PackageManager.DONT_KILL_APP
        )
        packageManager.setComponentEnabledSetting(
            darkAlias,
            if (icon == "dark") {
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED
            } else {
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED
            },
            PackageManager.DONT_KILL_APP
        )
    }
}
