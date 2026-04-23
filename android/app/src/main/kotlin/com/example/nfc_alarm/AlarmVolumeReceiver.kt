package com.example.nfc_alarm

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.AudioManager

class AlarmVolumeReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val maxVolume = audioManager.getStreamMaxVolume(AudioManager.STREAM_ALARM)

        // 원래 볼륨 저장
        val original = audioManager.getStreamVolume(AudioManager.STREAM_ALARM)
        val prefs = context.getSharedPreferences("alarm_volume_prefs", Context.MODE_PRIVATE)
        prefs.edit().putInt("original_alarm_volume", original).apply()

        // 알람 스트림 볼륨을 앱 설정값으로 고정
        val fraction = intent.getDoubleExtra("volume", 1.0).toFloat()
        val target = (fraction * maxVolume).toInt().coerceIn(0, maxVolume)
        audioManager.setStreamVolume(AudioManager.STREAM_ALARM, target, 0)
    }
}
