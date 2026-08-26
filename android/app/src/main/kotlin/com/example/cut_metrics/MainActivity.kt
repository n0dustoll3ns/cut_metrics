package com.example.cut_metrics

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val TAG = "MainActivity"
        private const val CHANNEL = "cut_metrics/app_settings"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "openAppDetails" -> {
                    // Настройки → Приложения → Cut Metrics (раздел «Разрешения»).
                    // Выбор пользователя (2026-08-26): кнопка при отказе разрешений
                    // Health Connect ведёт именно сюда.
                    try {
                        val intent = Intent(
                            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            Uri.fromParts("package", packageName, null),
                        )
                        startActivity(intent)
                        result.success(true)
                    } catch (e: ActivityNotFoundException) {
                        Log.w(TAG, "ACTION_APPLICATION_DETAILS_SETTINGS not found", e)
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}

