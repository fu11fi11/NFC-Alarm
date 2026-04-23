import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';
import '../constants/app_constants.dart';
import '../services/app_logger.dart';

// ─── 포그라운드 서비스 태스크 핸들러 ──────────────────────────────────────────
class AlarmTaskHandler extends TaskHandler {
    final _player = FlutterRingtonePlayer();
    int _elapsedSeconds = 0;
    String _soundType = 'alarm';
    double _volume = 1.0;

    @override
    Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
        final prefs = await SharedPreferences.getInstance();
        _volume = prefs.getDouble('active_alarm_volume') ?? 1.0;
        _soundType = prefs.getString('active_alarm_sound') ?? 'alarm';
        appLog(LogTag.service, '포그라운드 서비스 시작 — sound: $_soundType, volume: $_volume');
        await _playSound();
        if (await Vibration.hasVibrator()) {
            Vibration.vibrate(pattern: [0, 800, 400, 800], repeat: 0);
        }
    }

    Future<void> _playSound() async {
        switch (_soundType) {
            case 'notification':
                await _player.playNotification(looping: true, volume: _volume, asAlarm: true);
            case 'ringtone':
                await _player.playRingtone(looping: true, volume: _volume, asAlarm: true);
            case 'silent':
                break;
            default:
                await _player.playAlarm(looping: true, volume: _volume, asAlarm: true);
        }
    }

    @override
    void onRepeatEvent(DateTime timestamp) {
        _elapsedSeconds += 3;
        if (_elapsedSeconds >= AppConstants.autoOffSeconds) {
            appLog(LogTag.service, '알람 자동 꺼짐 (${AppConstants.autoOffSeconds}초 초과)');
            FlutterForegroundTask.sendDataToMain('alarm_auto_off');
            FlutterForegroundTask.stopService();
            return;
        }
        FlutterForegroundTask.launchApp();
    }

    @override
    void onReceiveData(Object data) {
        final msg = data.toString();
        if (msg == 'mute_temporary') {
            appLog(LogTag.service, '임시 음소거 요청');
            _player.stop();
            Vibration.cancel();
        } else if (msg == 'resume_sound') {
            appLog(LogTag.service, '소리 재시작 요청');
            _playSound();
            Vibration.hasVibrator().then((h) {
                if (h) Vibration.vibrate(pattern: [0, 800, 400, 800], repeat: 0);
            });
        }
    }

    @override
    Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
        appLog(LogTag.service, '포그라운드 서비스 종료 — isTimeout: $isTimeout');
        await _player.stop();
        Vibration.cancel();
    }
}
