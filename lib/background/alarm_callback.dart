import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_constants.dart';
import '../services/app_logger.dart';
import 'alarm_task_handler.dart';

// ─── AlarmManager 콜백 ────────────────────────────────────────────────────────
// 별도 isolate에서 실행 — Riverpod 접근 불가, SharedPreferences 직접 사용
@pragma('vm:entry-point')
Future<void> alarmFiredCallback(int id) async {
    WidgetsFlutterBinding.ensureInitialized();
    appLog(LogTag.alarm, '알람 발동 — AlarmManager ID: $id');

    try {
        final prefs = await SharedPreferences.getInstance();

        // 다중 NFC UID 로드 (구버전 단일 키 하위 호환)
        final nfcUids = prefs.getStringList('alarm_nfc_uids_$id');
        if (nfcUids != null && nfcUids.isNotEmpty) {
            await prefs.setStringList('active_nfc_uids', nfcUids);
        } else {
            final oldUid = prefs.getString('alarm_nfc_uid_$id');
            if (oldUid != null) {
                await prefs.setStringList('active_nfc_uids', [oldUid]);
            } else {
                await prefs.remove('active_nfc_uids');
            }
        }

        final volume = prefs.getDouble('alarm_volume_$id') ?? 1.0;
        final sound  = prefs.getString('alarm_sound_$id') ?? 'alarm';
        await prefs.setDouble('active_alarm_volume', volume);
        await prefs.setString('active_alarm_sound', sound);
        await prefs.setInt('active_alarm_start_ms', DateTime.now().millisecondsSinceEpoch);

        try {
            await AndroidIntent(
                action: 'com.example.nfc_alarm.SET_ALARM_VOLUME',
                package: AppConstants.packageName,
                componentName: '${AppConstants.packageName}.AlarmVolumeReceiver',
                arguments: <String, dynamic>{'volume': volume},
            ).sendBroadcast();
        } catch (_) {}
    } catch (_) {}

    FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
            channelId: 'alarm_service_channel',
            channelName: '알람 서비스',
            channelImportance: NotificationChannelImportance.HIGH,
            priority: NotificationPriority.HIGH,
        ),
        iosNotificationOptions: const IOSNotificationOptions(showNotification: false),
        foregroundTaskOptions: ForegroundTaskOptions(
            eventAction: ForegroundTaskEventAction.repeat(3000),
            autoRunOnBoot: false,
        ),
    );
    await FlutterForegroundTask.startService(
        serviceTypes: [ForegroundServiceTypes.dataSync],
        notificationTitle: '⏰ 알람이 울리고 있습니다',
        notificationText: 'NFC 태그를 스캔해서 알람을 끄세요',
        callback: alarmTaskCallback,
    );

    try {
        await const AndroidIntent(
            action: 'android.intent.action.MAIN',
            package: AppConstants.packageName,
            flags: [
                Flag.FLAG_ACTIVITY_NEW_TASK,
                Flag.FLAG_ACTIVITY_SINGLE_TOP,
                Flag.FLAG_ACTIVITY_REORDER_TO_FRONT,
            ],
        ).launch();
    } catch (_) {}

    final notificationsPlugin = FlutterLocalNotificationsPlugin();
    await notificationsPlugin.initialize(const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ));
    await notificationsPlugin.show(
        1, '⏰ 알람!', 'NFC 태그를 스캔해서 알람을 끄세요',
        const NotificationDetails(android: AndroidNotificationDetails(
            'alarm_channel', '알람',
            channelDescription: 'NFC 알람',
            importance: Importance.max,
            priority: Priority.high,
            fullScreenIntent: true,
            ongoing: true,
        )),
    );
    FlutterForegroundTask.sendDataToMain('alarm_triggered');
}

@pragma('vm:entry-point')
void alarmTaskCallback() => FlutterForegroundTask.setTaskHandler(AlarmTaskHandler());
