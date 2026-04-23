import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// ─── 알림 서비스 ──────────────────────────────────────────────────────────────
class NotificationService {
    static final NotificationService instance = NotificationService._();
    NotificationService._();

    final _plugin = FlutterLocalNotificationsPlugin();
    FlutterLocalNotificationsPlugin get plugin => _plugin;

    Future<void> initialize() async {
        await _plugin.initialize(const InitializationSettings(
            android: AndroidInitializationSettings('@mipmap/ic_launcher'),
            iOS: DarwinInitializationSettings(
                requestAlertPermission: true,
                requestBadgePermission: true,
                requestSoundPermission: true,
            ),
        ));
        final androidPlugin = _plugin
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        await androidPlugin?.requestNotificationsPermission();
        await androidPlugin?.requestExactAlarmsPermission();
    }

    Future<void> cancelAlarm() => _plugin.cancel(1);
}
