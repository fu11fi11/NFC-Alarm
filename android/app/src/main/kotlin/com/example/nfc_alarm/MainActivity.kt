package com.example.nfc_alarm

import android.media.AudioManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.example.nfc_alarm/overlay")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canDrawOverlays" -> result.success(Settings.canDrawOverlays(this))
                    "restoreAlarmVolume" -> {
                        val prefs = getSharedPreferences("alarm_volume_prefs", MODE_PRIVATE)
                        val original = prefs.getInt("original_alarm_volume", -1)
                        if (original >= 0) {
                            val am = getSystemService(AUDIO_SERVICE) as AudioManager
                            am.setStreamVolume(AudioManager.STREAM_ALARM, original, 0)
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
