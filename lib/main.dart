import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'app.dart';
import 'services/notification_service.dart';

// ─── 앱 진입점 ────────────────────────────────────────────────────────────────
void main() async {
    WidgetsFlutterBinding.ensureInitialized();
    tz.initializeTimeZones();
    await AndroidAlarmManager.initialize();
    FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
            channelId: 'alarm_service_channel',
            channelName: '알람 서비스',
            channelImportance: NotificationChannelImportance.HIGH,
            priority: NotificationPriority.HIGH,
        ),
        iosNotificationOptions: const IOSNotificationOptions(showNotification: false),
        foregroundTaskOptions: ForegroundTaskOptions(
            eventAction: ForegroundTaskEventAction.nothing(),
            autoRunOnBoot: false,
        ),
    );
    await NotificationService.instance.initialize();
    runApp(const ProviderScope(child: NfcAlarmApp()));
}
