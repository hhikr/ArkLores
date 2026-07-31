package com.arklores.arklores

import android.content.ComponentName
import android.content.pm.PackageManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val channelName = "arklores/app_icon"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
