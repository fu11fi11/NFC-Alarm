import 'dart:async';
import 'dart:convert';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:vibration/vibration.dart';

// ─── NFC 태그 모델 ─────────────────────────────────────────────────────────
class NfcTagData {
  final int id;
  final String name;
  final String uid;
  const NfcTagData({required this.id, required this.name, required this.uid});
  NfcTagData copyWith({String? name, String? uid}) =>
      NfcTagData(id: id, name: name ?? this.name, uid: uid ?? this.uid);
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'uid': uid};
  factory NfcTagData.fromJson(Map<String, dynamic> j) =>
      NfcTagData(id: j['id'] as int, name: j['name'] as String, uid: j['uid'] as String);
}

// ─── 알람 모델 ─────────────────────────────────────────────────────────────
class AlarmData {
  final int id;
  final int hour;
  final int minute;
  final List<int> days;
  final bool enabled;
  final List<int> nfcTagIds;       // 다중 NFC 태그 (빈 목록 = 아무 태그나)
  final String soundType;
  final double volume;

  const AlarmData({
    required this.id, required this.hour, required this.minute,
    required this.days, this.enabled = true,
    this.nfcTagIds = const [], this.soundType = 'alarm', this.volume = 1.0,
  });

  AlarmData copyWith({
    int? hour, int? minute, List<int>? days, bool? enabled,
    List<int>? nfcTagIds, String? soundType, double? volume,
  }) => AlarmData(
    id: id, hour: hour ?? this.hour, minute: minute ?? this.minute,
    days: days ?? this.days, enabled: enabled ?? this.enabled,
    nfcTagIds: nfcTagIds ?? this.nfcTagIds,
    soundType: soundType ?? this.soundType, volume: volume ?? this.volume,
  );

  Map<String, dynamic> toJson() => {
    'id': id, 'hour': hour, 'minute': minute, 'days': days,
    'enabled': enabled, 'nfcTagIds': nfcTagIds, 'soundType': soundType, 'volume': volume,
  };

  factory AlarmData.fromJson(Map<String, dynamic> j) => AlarmData(
    id: j['id'] as int, hour: j['hour'] as int, minute: j['minute'] as int,
    days: List<int>.from(j['days'] as List), enabled: j['enabled'] as bool,
    // 구버전 단일 nfcTagId 마이그레이션
    nfcTagIds: j['nfcTagIds'] != null
        ? List<int>.from(j['nfcTagIds'] as List)
        : (j['nfcTagId'] != null ? [j['nfcTagId'] as int] : []),
    soundType: (j['soundType'] as String?) ?? 'alarm',
    volume: (j['volume'] as num?)?.toDouble() ?? 1.0,
  );
}

// ─── 체인 단계 모델 ─────────────────────────────────────────────────────────
class ChainStep {
  final int hour;
  final int minute;
  final String label;             // 단계 이름 (예: "기상", "헬스장")
  final List<int> nfcTagIds;
  final String soundType;
  final double volume;

  const ChainStep({
    required this.hour, required this.minute, this.label = '',
    this.nfcTagIds = const [], this.soundType = 'alarm', this.volume = 1.0,
  });

  ChainStep copyWith({
    int? hour, int? minute, String? label,
    List<int>? nfcTagIds, String? soundType, double? volume,
  }) => ChainStep(
    hour: hour ?? this.hour, minute: minute ?? this.minute,
    label: label ?? this.label, nfcTagIds: nfcTagIds ?? this.nfcTagIds,
    soundType: soundType ?? this.soundType, volume: volume ?? this.volume,
  );

  Map<String, dynamic> toJson() => {
    'hour': hour, 'minute': minute, 'label': label,
    'nfcTagIds': nfcTagIds, 'soundType': soundType, 'volume': volume,
  };

  factory ChainStep.fromJson(Map<String, dynamic> j) => ChainStep(
    hour: j['hour'] as int, minute: j['minute'] as int,
    label: (j['label'] as String?) ?? '',
    nfcTagIds: List<int>.from((j['nfcTagIds'] as List?) ?? []),
    soundType: (j['soundType'] as String?) ?? 'alarm',
    volume: (j['volume'] as num?)?.toDouble() ?? 1.0,
  );
}

// ─── 알람 체인 모델 ─────────────────────────────────────────────────────────
class AlarmChain {
  final int id;
  final String name;
  final List<int> days;           // 체인 전체 공유 요일
  final bool enabled;
  final List<ChainStep> steps;

  const AlarmChain({
    required this.id, required this.name,
    this.days = const [], this.enabled = true, this.steps = const [],
  });

  AlarmChain copyWith({
    String? name, List<int>? days, bool? enabled, List<ChainStep>? steps,
  }) => AlarmChain(
    id: id, name: name ?? this.name, days: days ?? this.days,
    enabled: enabled ?? this.enabled, steps: steps ?? this.steps,
  );

  Map<String, dynamic> toJson() => {
    'id': id, 'name': name, 'days': days, 'enabled': enabled,
    'steps': steps.map((s) => s.toJson()).toList(),
  };

  factory AlarmChain.fromJson(Map<String, dynamic> j) => AlarmChain(
    id: j['id'] as int, name: j['name'] as String,
    days: List<int>.from((j['days'] as List?) ?? []),
    enabled: (j['enabled'] as bool?) ?? true,
    steps: ((j['steps'] as List?) ?? [])
        .map((e) => ChainStep.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

// 체인 AlarmManager ID: 10000 + chainId*100 + stepIdx*10 + weekday
int chainAmId(int chainId, int stepIdx, int weekday) =>
    10000 + chainId * 100 + stepIdx * 10 + weekday;

DateTime nextOccurrence(int weekday, int hour, int minute) {
  final now = DateTime.now();
  final daysUntil = (weekday - now.weekday + 7) % 7;
  var candidate = DateTime(now.year, now.month, now.day, hour, minute)
      .add(Duration(days: daysUntil));
  if (!candidate.isAfter(now)) candidate = candidate.add(const Duration(days: 7));
  return candidate;
}

// ─── AlarmManager 콜백 ─────────────────────────────────────────────────────
@pragma('vm:entry-point')
Future<void> alarmFiredCallback(int id) async {
  WidgetsFlutterBinding.ensureInitialized();

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
        package: 'com.example.nfc_alarm',
        componentName: 'com.example.nfc_alarm.AlarmVolumeReceiver',
        arguments: <String, dynamic>{'volume': volume},
      ).sendBroadcast();
    } catch (_) {}
  } catch (_) {}

  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'alarm_service_channel', channelName: '알람 서비스',
      channelImportance: NotificationChannelImportance.HIGH,
      priority: NotificationPriority.HIGH,
    ),
    iosNotificationOptions: const IOSNotificationOptions(showNotification: false),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.repeat(3000), autoRunOnBoot: false,
    ),
  );
  await FlutterForegroundTask.startService(
    serviceTypes: [ForegroundServiceTypes.dataSync],
    notificationTitle: '⏰ 알람이 울리고 있습니다',
    notificationText: 'NFC 태그를 스캔해서 알람을 끄세요',
    callback: alarmTaskCallback,
  );

  try {
    await AndroidIntent(
      action: 'android.intent.action.MAIN',
      package: 'com.example.nfc_alarm',
      flags: [Flag.FLAG_ACTIVITY_NEW_TASK, Flag.FLAG_ACTIVITY_SINGLE_TOP,
              Flag.FLAG_ACTIVITY_REORDER_TO_FRONT],
    ).launch();
  } catch (_) {}

  final notificationsPlugin = FlutterLocalNotificationsPlugin();
  await notificationsPlugin.initialize(const InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
  ));
  await notificationsPlugin.show(1, '⏰ 알람!', 'NFC 태그를 스캔해서 알람을 끄세요',
    const NotificationDetails(android: AndroidNotificationDetails(
      'alarm_channel', '알람', channelDescription: 'NFC 알람',
      importance: Importance.max, priority: Priority.high,
      fullScreenIntent: true, ongoing: true,
    )),
  );
  FlutterForegroundTask.sendDataToMain('alarm_triggered');
}

@pragma('vm:entry-point')
void alarmTaskCallback() => FlutterForegroundTask.setTaskHandler(AlarmTaskHandler());

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
    await _playSound();
    if (await Vibration.hasVibrator()) Vibration.vibrate(pattern: [0, 800, 400, 800], repeat: 0);
  }

  Future<void> _playSound() async {
    switch (_soundType) {
      case 'notification': await _player.playNotification(looping: true, volume: _volume, asAlarm: true); break;
      case 'ringtone':     await _player.playRingtone(looping: true, volume: _volume, asAlarm: true); break;
      case 'silent': break;
      default: await _player.playAlarm(looping: true, volume: _volume, asAlarm: true);
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    _elapsedSeconds += 3;
    if (_elapsedSeconds >= 300) {
      FlutterForegroundTask.sendDataToMain('alarm_auto_off');
      FlutterForegroundTask.stopService();
      return;
    }
    FlutterForegroundTask.launchApp();
  }

  @override
  void onReceiveData(Object data) {
    final msg = data.toString();
    if (msg == 'mute_temporary') { _player.stop(); Vibration.cancel(); }
    else if (msg == 'resume_sound') {
      _playSound();
      Vibration.hasVibrator().then((h) { if (h) Vibration.vibrate(pattern: [0, 800, 400, 800], repeat: 0); });
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    await _player.stop(); Vibration.cancel();
  }
}

// ─── 앱 초기화 ─────────────────────────────────────────────────────────────
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  await AndroidAlarmManager.initialize();
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'alarm_service_channel', channelName: '알람 서비스',
      channelImportance: NotificationChannelImportance.HIGH, priority: NotificationPriority.HIGH,
    ),
    iosNotificationOptions: const IOSNotificationOptions(showNotification: false),
    foregroundTaskOptions: ForegroundTaskOptions(eventAction: ForegroundTaskEventAction.nothing(), autoRunOnBoot: false),
  );
  await flutterLocalNotificationsPlugin.initialize(const InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    iOS: DarwinInitializationSettings(requestAlertPermission: true, requestBadgePermission: true, requestSoundPermission: true),
  ));
  final androidPlugin = flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  await androidPlugin?.requestNotificationsPermission();
  await androidPlugin?.requestExactAlarmsPermission();
  runApp(const NfcAlarmApp());
}

class NfcAlarmApp extends StatelessWidget {
  const NfcAlarmApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'NFC 알람', debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1A1A2E), brightness: Brightness.dark),
      useMaterial3: true,
    ),
    home: const AlarmListScreen(),
  );
}

// ─── 알람 목록 화면 ─────────────────────────────────────────────────────────
class AlarmListScreen extends StatefulWidget {
  const AlarmListScreen({super.key});
  @override
  State<AlarmListScreen> createState() => _AlarmListScreenState();
}

class _AlarmListScreenState extends State<AlarmListScreen> {
  static const _overlayChannel = MethodChannel('com.example.nfc_alarm/overlay');
  static const _dayLabels = ['월', '화', '수', '목', '금', '토', '일'];

  List<AlarmData> _alarms = [];
  List<NfcTagData> _nfcTags = [];
  List<AlarmChain> _chains = [];
  int _nextAlarmId = 0, _nextNfcTagId = 0, _nextChainId = 0;
  bool _alarmActive = false, _overlayGranted = true;
  List<String> _activeNfcUids = [];
  Timer? _countdownTimer;

  void _onServiceData(Object data) {
    final msg = data.toString();
    if (msg == 'alarm_triggered' && mounted && !_alarmActive) {
      setState(() => _alarmActive = true);
      _loadActiveNfcUids().then((_) => _pushAlarmScreen());
    } else if (msg == 'alarm_auto_off' && mounted && _alarmActive) {
      _dismissAlarm();
    }
  }

  @override
  void initState() {
    super.initState();
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.addTaskDataCallback(_onServiceData);
    _loadData();
    _checkOverlayPermission();
    _countdownTimer = Timer.periodic(const Duration(minutes: 1), (_) { if (mounted) setState(() {}); });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    FlutterForegroundTask.removeTaskDataCallback(_onServiceData);
    NfcManager.instance.stopSession();
    super.dispose();
  }

  Future<void> _loadActiveNfcUids() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() => _activeNfcUids = prefs.getStringList('active_nfc_uids') ?? []);
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();

    List<NfcTagData> tags = [];
    int nextTagId = 0;
    final tagsJson = prefs.getString('nfc_tags');
    if (tagsJson != null) {
      final list = jsonDecode(tagsJson) as List;
      tags = list.map((e) => NfcTagData.fromJson(e as Map<String, dynamic>)).toList();
      nextTagId = prefs.getInt('nfc_tag_next_id') ?? tags.fold(0, (m, t) => t.id >= m ? t.id + 1 : m);
    } else {
      final oldUid = prefs.getString('nfc_uid');
      if (oldUid != null) {
        tags = [NfcTagData(id: 0, name: '기본 태그', uid: oldUid)];
        nextTagId = 1;
        await prefs.setString('nfc_tags', jsonEncode(tags.map((t) => t.toJson()).toList()));
        await prefs.setInt('nfc_tag_next_id', nextTagId);
      }
    }

    List<AlarmData> alarms = [];
    int nextAlarmId = 0;
    final alarmsJson = prefs.getString('alarms');
    if (alarmsJson != null) {
      final list = jsonDecode(alarmsJson) as List;
      alarms = list.map((e) => AlarmData.fromJson(e as Map<String, dynamic>)).toList();
      nextAlarmId = prefs.getInt('alarm_next_id') ?? alarms.fold(0, (m, a) => a.id >= m ? a.id + 1 : m);
    } else {
      final hour = prefs.getInt('alarm_hour');
      if (hour != null) {
        final minute = prefs.getInt('alarm_minute') ?? 0;
        final daysStr = prefs.getString('alarm_days') ?? '';
        final enabled = prefs.getBool('alarm_enabled') ?? false;
        final days = daysStr.isEmpty ? <int>[] : daysStr.split(',').map(int.parse).toList();
        alarms = [AlarmData(id: 0, hour: hour, minute: minute, days: days, enabled: enabled,
          nfcTagIds: tags.isEmpty ? [] : [tags.first.id])];
        nextAlarmId = 1;
      }
    }

    List<AlarmChain> chains = [];
    int nextChainId = 0;
    final chainsJson = prefs.getString('chains');
    if (chainsJson != null) {
      final list = jsonDecode(chainsJson) as List;
      chains = list.map((e) => AlarmChain.fromJson(e as Map<String, dynamic>)).toList();
      nextChainId = prefs.getInt('chain_next_id') ?? chains.fold(0, (m, c) => c.id >= m ? c.id + 1 : m);
    }

    setState(() {
      _nfcTags = tags; _nextNfcTagId = nextTagId;
      _alarms = alarms; _nextAlarmId = nextAlarmId;
      _chains = chains; _nextChainId = nextChainId;
    });

    if (!mounted) return;
    if (await FlutterForegroundTask.isRunningService && mounted) {
      await _loadActiveNfcUids();
      setState(() => _alarmActive = true);
      _pushAlarmScreen();
    }
  }

  Future<void> _saveAlarms() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('alarms', jsonEncode(_alarms.map((a) => a.toJson()).toList()));
    await prefs.setInt('alarm_next_id', _nextAlarmId);
  }

  Future<void> _saveNfcTags() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('nfc_tags', jsonEncode(_nfcTags.map((t) => t.toJson()).toList()));
    await prefs.setInt('nfc_tag_next_id', _nextNfcTagId);
  }

  Future<void> _saveChains() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('chains', jsonEncode(_chains.map((c) => c.toJson()).toList()));
    await prefs.setInt('chain_next_id', _nextChainId);
  }

  Future<void> _scheduleAlarm(AlarmData alarm) async {
    final prefs = await SharedPreferences.getInstance();
    for (int d = 1; d <= 7; d++) {
      final amId = alarm.id * 10 + d;
      await AndroidAlarmManager.cancel(amId);
      await prefs.remove('alarm_nfc_uids_$amId');
      await prefs.remove('alarm_nfc_uid_$amId');
      await prefs.remove('alarm_volume_$amId');
      await prefs.remove('alarm_sound_$amId');
    }
    if (!alarm.enabled || alarm.days.isEmpty) return;
    final uids = _resolveUids(alarm.nfcTagIds);
    for (final day in alarm.days) {
      final amId = alarm.id * 10 + day;
      if (uids.isNotEmpty) await prefs.setStringList('alarm_nfc_uids_$amId', uids);
      await prefs.setDouble('alarm_volume_$amId', alarm.volume);
      await prefs.setString('alarm_sound_$amId', alarm.soundType);
      await AndroidAlarmManager.oneShotAt(nextOccurrence(day, alarm.hour, alarm.minute),
        amId, alarmFiredCallback, alarmClock: true, exact: true, wakeup: true, rescheduleOnReboot: true);
    }
  }

  Future<void> _scheduleChain(AlarmChain chain) async {
    final prefs = await SharedPreferences.getInstance();
    for (int si = 0; si < 20; si++) {
      for (int d = 1; d <= 7; d++) {
        final amId = chainAmId(chain.id, si, d);
        await AndroidAlarmManager.cancel(amId);
        await prefs.remove('alarm_nfc_uids_$amId');
        await prefs.remove('alarm_volume_$amId');
        await prefs.remove('alarm_sound_$amId');
      }
    }
    if (!chain.enabled || chain.days.isEmpty || chain.steps.isEmpty) return;
    for (int si = 0; si < chain.steps.length; si++) {
      final step = chain.steps[si];
      final uids = _resolveUids(step.nfcTagIds);
      for (final day in chain.days) {
        final amId = chainAmId(chain.id, si, day);
        if (uids.isNotEmpty) await prefs.setStringList('alarm_nfc_uids_$amId', uids);
        await prefs.setDouble('alarm_volume_$amId', step.volume);
        await prefs.setString('alarm_sound_$amId', step.soundType);
        await AndroidAlarmManager.oneShotAt(nextOccurrence(day, step.hour, step.minute),
          amId, alarmFiredCallback, alarmClock: true, exact: true, wakeup: true, rescheduleOnReboot: true);
      }
    }
  }

  Future<void> _skipChainStepToday(AlarmChain chain, int stepIdx) async {
    final now = DateTime.now();
    final today = now.weekday;
    if (!chain.days.contains(today)) return;
    final step = chain.steps[stepIdx];
    final todayTime = DateTime(now.year, now.month, now.day, step.hour, step.minute);
    if (!todayTime.isAfter(now)) return;
    final prefs = await SharedPreferences.getInstance();
    final amId = chainAmId(chain.id, stepIdx, today);
    await AndroidAlarmManager.cancel(amId);
    final uids = _resolveUids(step.nfcTagIds);
    final nextTime = todayTime.add(const Duration(days: 7));
    if (uids.isNotEmpty) await prefs.setStringList('alarm_nfc_uids_$amId', uids);
    await prefs.setDouble('alarm_volume_$amId', step.volume);
    await prefs.setString('alarm_sound_$amId', step.soundType);
    await AndroidAlarmManager.oneShotAt(nextTime, amId, alarmFiredCallback,
      alarmClock: true, exact: true, wakeup: true, rescheduleOnReboot: true);
  }

  List<String> _resolveUids(List<int> tagIds) {
    final uids = <String>[];
    for (final id in tagIds) {
      for (final t in _nfcTags) { if (t.id == id) { uids.add(t.uid); break; } }
    }
    return uids;
  }

  (bool, String?) _checkInStatus(AlarmChain chain) {
    if (!chain.enabled) return (false, '체인 비활성화');
    if (chain.steps.length < 2) return (false, '단계 2개 이상 필요');
    if (!chain.steps.skip(1).any((s) => s.nfcTagIds.isNotEmpty)) {
      return (false, '2단계 이후에 NFC 태그 필요');
    }
    if (chain.days.isEmpty) return (false, '요일 미설정');
    final now = DateTime.now();
    if (!chain.days.contains(now.weekday)) return (false, '오늘은 이 체인 없는 날');
    final first = chain.steps.first;
    final firstToday = DateTime(now.year, now.month, now.day, first.hour, first.minute);
    if (!firstToday.isAfter(now)) return (false, '첫 단계 이미 지남');
    final diff = firstToday.difference(now);
    if (diff.inMinutes > 120) {
      return (false, '${diff.inHours}시간 ${diff.inMinutes % 60}분 후 사용 가능');
    }
    return (true, null);
  }

  String _countdownForChain(AlarmChain chain) {
    if (!chain.enabled || chain.days.isEmpty || chain.steps.isEmpty) return '';
    final first = chain.steps.first;
    final next = chain.days.map((d) => nextOccurrence(d, first.hour, first.minute))
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final diff = next.difference(DateTime.now());
    return '${diff.inHours}시간 ${diff.inMinutes % 60}분 후 시작';
  }

  void _pushAlarmScreen() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => AlarmRingingScreen(onNfcScan: _startNfcScan, onDismiss: _dismissAlarm),
    ));
  }

  void _dismissAlarm() {
    setState(() => _alarmActive = false);
    flutterLocalNotificationsPlugin.cancel(1);
    FlutterForegroundTask.stopService();
    SharedPreferences.getInstance().then((p) {
      p.remove('active_nfc_uids'); p.remove('active_alarm_start_ms');
    });
    _overlayChannel.invokeMethod('restoreAlarmVolume').catchError((_) {});
    for (final alarm in _alarms) { _scheduleAlarm(alarm); }
    for (final chain in _chains) { _scheduleChain(chain); }
  }

  Future<void> _startNfcScan(Function(bool) onResult) async {
    final isAvailable = await NfcManager.instance.isAvailable();
    if (!isAvailable) { onResult(false); return; }
    NfcManager.instance.startSession(onDiscovered: (NfcTag tag) async {
      final uid = _extractUid(tag);
      NfcManager.instance.stopSession();
      if (_activeNfcUids.isNotEmpty) {
        onResult(_activeNfcUids.contains(uid));
      } else {
        onResult(_nfcTags.any((t) => t.uid == uid));
      }
    });
  }

  Future<void> _toggleAlarm(AlarmData alarm, bool enabled) async {
    final updated = alarm.copyWith(enabled: enabled);
    final idx = _alarms.indexWhere((a) => a.id == alarm.id);
    if (idx == -1) return;
    setState(() => _alarms[idx] = updated);
    await _saveAlarms(); await _scheduleAlarm(updated);
  }

  Future<void> _openEditScreen(AlarmData? alarm) async {
    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => AlarmEditScreen(
        alarm: alarm, nfcTags: _nfcTags,
        onSave: (hour, minute, days, nfcTagIds, soundType, volume) async {
          if (alarm == null) {
            final newAlarm = AlarmData(id: _nextAlarmId++, hour: hour, minute: minute,
              days: days, nfcTagIds: nfcTagIds, soundType: soundType, volume: volume);
            setState(() => _alarms.add(newAlarm));
            await _saveAlarms(); await _scheduleAlarm(newAlarm);
          } else {
            final updated = alarm.copyWith(hour: hour, minute: minute, days: days,
              nfcTagIds: nfcTagIds, soundType: soundType, volume: volume);
            final idx = _alarms.indexWhere((a) => a.id == alarm.id);
            if (idx != -1) setState(() => _alarms[idx] = updated);
            await _saveAlarms(); await _scheduleAlarm(updated);
          }
        },
        onDelete: alarm == null ? null : () async {
          final prefs = await SharedPreferences.getInstance();
          for (int d = 1; d <= 7; d++) {
            final amId = alarm.id * 10 + d;
            await AndroidAlarmManager.cancel(amId);
            await prefs.remove('alarm_nfc_uids_$amId');
            await prefs.remove('alarm_volume_$amId'); await prefs.remove('alarm_sound_$amId');
          }
          setState(() => _alarms.removeWhere((a) => a.id == alarm.id));
          await _saveAlarms();
        },
      ),
    ));
  }

  Future<void> _openNfcTagScreen() async {
    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => NfcTagListScreen(
        nfcTags: _nfcTags, nextId: _nextNfcTagId,
        onChanged: (tags, nextId) async {
          setState(() { _nfcTags = tags; _nextNfcTagId = nextId; });
          await _saveNfcTags();
          // 삭제된 태그 참조 제거 — 독립 알람
          bool changed = false;
          final updatedAlarms = _alarms.map((a) {
            final filtered = a.nfcTagIds.where((id) => tags.any((t) => t.id == id)).toList();
            if (filtered.length != a.nfcTagIds.length) { changed = true; return a.copyWith(nfcTagIds: filtered); }
            return a;
          }).toList();
          if (changed) { setState(() => _alarms = updatedAlarms); await _saveAlarms(); }
          // 삭제된 태그 참조 제거 — 체인 단계
          bool chainsChanged = false;
          final updatedChains = _chains.map((c) {
            final updatedSteps = c.steps.map((s) {
              final filtered = s.nfcTagIds.where((id) => tags.any((t) => t.id == id)).toList();
              if (filtered.length != s.nfcTagIds.length) { chainsChanged = true; return s.copyWith(nfcTagIds: filtered); }
              return s;
            }).toList();
            return c.copyWith(steps: updatedSteps);
          }).toList();
          if (chainsChanged) {
            setState(() => _chains = updatedChains); await _saveChains();
            for (final chain in _chains) await _scheduleChain(chain);
          }
        },
      ),
    ));
  }

  Future<void> _openChainEditScreen(AlarmChain? chain) async {
    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => AlarmChainEditScreen(
        chain: chain, nfcTags: _nfcTags,
        onSave: (name, days, steps) async {
          if (chain == null) {
            final newChain = AlarmChain(id: _nextChainId++, name: name, days: days, steps: steps);
            setState(() => _chains.add(newChain));
            await _saveChains(); await _scheduleChain(newChain);
          } else {
            final updated = chain.copyWith(name: name, days: days, steps: steps);
            final idx = _chains.indexWhere((c) => c.id == chain.id);
            if (idx != -1) setState(() => _chains[idx] = updated);
            await _saveChains(); await _scheduleChain(updated);
          }
        },
        onDelete: chain == null ? null : () async {
          await _scheduleChain(chain.copyWith(enabled: false, steps: [])); // 알람 취소
          setState(() => _chains.removeWhere((c) => c.id == chain.id));
          await _saveChains();
        },
      ),
    ));
  }

  Future<void> _startChainCheckIn(AlarmChain chain) async {
    final (canCheck, reason) = _checkInStatus(chain);
    if (!canCheck) { _showSnackBar(reason ?? '체크인 불가'); return; }
    final isAvailable = await NfcManager.instance.isAvailable();
    if (!isAvailable) { _showSnackBar('NFC를 사용할 수 없습니다'); return; }
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (_) => _ChainCheckInDialog(
        chain: chain, nfcTags: _nfcTags,
        onSkip: (indices) async {
          for (final i in indices) await _skipChainStepToday(chain, i);
        },
      ),
    );
  }

  Future<void> _checkOverlayPermission() async {
    final granted = await _overlayChannel.invokeMethod<bool>('canDrawOverlays') ?? false;
    if (mounted) setState(() => _overlayGranted = granted);
  }

  Future<void> _requestOverlayPermission() async {
    await AndroidIntent(action: 'android.settings.action.MANAGE_OVERLAY_PERMISSION',
        data: 'package:com.example.nfc_alarm').launch();
    await Future.delayed(const Duration(seconds: 1));
    await _checkOverlayPermission();
  }

  String? _extractUid(NfcTag tag) {
    List<int>? id;
    for (final key in ['nfca', 'nfcb', 'nfcf', 'nfcv']) {
      if (tag.data[key] != null) { id = List<int>.from(tag.data[key]['identifier']); break; }
    }
    if (id == null) return null;
    return id.map((e) => e.toRadixString(16).padLeft(2, '0')).join(':');
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 2)));
  }

  String _countdownFor(AlarmData alarm) {
    if (!alarm.enabled || alarm.days.isEmpty) return '';
    final next = alarm.days.map((d) => nextOccurrence(d, alarm.hour, alarm.minute))
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final diff = next.difference(DateTime.now());
    return '${diff.inHours}시간 ${diff.inMinutes % 60}분 후';
  }

  String _nfcTagNamesFor(AlarmData alarm) {
    if (alarm.nfcTagIds.isEmpty) return '태그 미지정';
    final names = alarm.nfcTagIds.map((id) {
      for (final t in _nfcTags) { if (t.id == id) return t.name; }
      return null;
    }).whereType<String>().toList();
    if (names.isEmpty) return '태그 없음';
    if (names.length <= 2) return names.join(', ');
    return '${names.take(2).join(', ')} 외 ${names.length - 2}개';
  }

  Widget _buildMainList() {
    final hasContent = _chains.isNotEmpty || _alarms.isNotEmpty;
    if (!hasContent) {
      return const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.alarm_off, size: 64, color: Colors.grey),
        SizedBox(height: 16),
        Text('알람이 없습니다', style: TextStyle(color: Colors.grey, fontSize: 16)),
        SizedBox(height: 8),
        Text('+ 버튼으로 알람을 추가하세요', style: TextStyle(color: Colors.grey, fontSize: 13)),
      ]));
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      children: [
        if (_chains.isNotEmpty) ...[
          Row(children: [
            const Icon(Icons.link, color: Colors.white38, size: 14),
            const SizedBox(width: 6),
            const Text('알람 체인', style: TextStyle(color: Colors.white38, fontSize: 12)),
            const Spacer(),
            TextButton(
              onPressed: () => _openChainEditScreen(null),
              style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero),
              child: const Text('+ 새 체인', style: TextStyle(color: Colors.white38, fontSize: 11)),
            ),
          ]),
          const SizedBox(height: 8),
          ...(_chains.map((chain) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _ChainCard(
              chain: chain, nfcTags: _nfcTags,
              countdown: _countdownForChain(chain),
              checkInStatus: _checkInStatus(chain),
              dayLabels: _dayLabels,
              onTap: () => _openChainEditScreen(chain),
              onCheckIn: () => _startChainCheckIn(chain),
            ),
          ))),
          if (_alarms.isNotEmpty) const SizedBox(height: 8),
        ],
        if (_alarms.isNotEmpty) ...[
          if (_chains.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: const [
                Icon(Icons.alarm, color: Colors.white38, size: 14),
                SizedBox(width: 6),
                Text('개별 알람', style: TextStyle(color: Colors.white38, fontSize: 12)),
              ]),
            ),
          ...(_alarms.map((alarm) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _AlarmListItem(
              alarm: alarm, dayLabels: _dayLabels,
              countdownText: _countdownFor(alarm),
              nfcTagName: _nfcTagNamesFor(alarm),
              onTap: () => _openEditScreen(alarm),
              onToggle: (v) => _toggleAlarm(alarm, v),
            ),
          ))),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      drawer: Drawer(
        backgroundColor: const Color(0xFF16213E),
        child: ListView(padding: EdgeInsets.zero, children: [
          const DrawerHeader(
            decoration: BoxDecoration(color: Color(0xFF0F3460)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.end, children: [
              Icon(Icons.alarm, color: Colors.white, size: 40),
              SizedBox(height: 10),
              Text('NFC 알람', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
            ]),
          ),
          ListTile(
            leading: const Icon(Icons.link, color: Colors.white70),
            title: const Text('알람 체인 관리', style: TextStyle(color: Colors.white)),
            onTap: () { Navigator.pop(context); _openChainEditScreen(null); },
          ),
          ListTile(
            leading: const Icon(Icons.nfc, color: Colors.white70),
            title: const Text('NFC 태그 관리', style: TextStyle(color: Colors.white)),
            trailing: _nfcTags.isEmpty ? const Badge(label: Text('!')) : null,
            onTap: () { Navigator.pop(context); _openNfcTagScreen(); },
          ),
          const Divider(color: Colors.white12),
          ListTile(
            leading: const Icon(Icons.science_outlined, color: Colors.grey, size: 20),
            title: const Text('5초 후 알람 테스트', style: TextStyle(color: Colors.grey, fontSize: 13)),
            onTap: () async {
              Navigator.pop(context);
              await AndroidAlarmManager.oneShotAt(DateTime.now().add(const Duration(seconds: 5)),
                99, alarmFiredCallback, alarmClock: true, exact: true, wakeup: true);
              _showSnackBar('🧪 5초 후 알람 테스트');
            },
          ),
        ]),
      ),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('NFC 알람', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(children: [
        if (!_overlayGranted)
          GestureDetector(
            onTap: _requestOverlayPermission,
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.withOpacity(0.6)),
              ),
              child: const Row(children: [
                Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 18),
                SizedBox(width: 8),
                Expanded(child: Text('다른 앱 위에 표시 권한 없음 — 탭하여 허용',
                    style: TextStyle(color: Colors.orange, fontSize: 12))),
              ]),
            ),
          ),
        Expanded(child: _buildMainList()),
      ]),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEditScreen(null),
        backgroundColor: const Color(0xFF0F3460),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}

// ─── 알람 체인 카드 ─────────────────────────────────────────────────────────
class _ChainCard extends StatelessWidget {
  final AlarmChain chain;
  final List<NfcTagData> nfcTags;
  final String countdown;
  final (bool, String?) checkInStatus;
  final List<String> dayLabels;
  final VoidCallback onTap;
  final VoidCallback onCheckIn;

  const _ChainCard({
    required this.chain, required this.nfcTags, required this.countdown,
    required this.checkInStatus, required this.dayLabels,
    required this.onTap, required this.onCheckIn,
  });

  String _stepTagSummary(ChainStep step) {
    if (step.nfcTagIds.isEmpty) return '태그 없음';
    final names = step.nfcTagIds.map((id) {
      for (final t in nfcTags) { if (t.id == id) return t.name; }
      return null;
    }).whereType<String>().toList();
    if (names.isEmpty) return '태그 없음';
    if (names.length == 1) return names.first;
    return '${names.first} 외 ${names.length - 1}개';
  }

  @override
  Widget build(BuildContext context) {
    final (canCheckIn, blockReason) = checkInStatus;
    final daysText = chain.days.isEmpty ? '요일 미설정'
        : chain.days.map((d) => dayLabels[d - 1]).join(' ');

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF0D1B3E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.blue.withOpacity(0.3)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.link, color: Colors.blue, size: 16),
            const SizedBox(width: 8),
            Expanded(child: Text(chain.name,
                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold))),
            GestureDetector(
              onTap: onCheckIn,
              child: Tooltip(
                message: canCheckIn ? '체인 체크인' : (blockReason ?? ''),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: canCheckIn ? Colors.green.withOpacity(0.2) : Colors.grey.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: canCheckIn ? Colors.green : Colors.grey.withOpacity(0.3)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.location_on, size: 13, color: canCheckIn ? Colors.green : Colors.grey),
                    const SizedBox(width: 4),
                    Text('체크인', style: TextStyle(fontSize: 11,
                        color: canCheckIn ? Colors.green : Colors.grey, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 14),
          if (chain.steps.isEmpty)
            const Text('단계 없음', style: TextStyle(color: Colors.grey, fontSize: 12))
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: List.generate(chain.steps.length * 2 - 1, (i) {
                  if (i.isOdd) return const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(Icons.arrow_forward, size: 14, color: Colors.white38),
                  );
                  final step = chain.steps[i ~/ 2];
                  final h = step.hour.toString().padLeft(2, '0');
                  final m = step.minute.toString().padLeft(2, '0');
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: const Color(0xFF16213E),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
                      Text('$h:$m', style: const TextStyle(
                          color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      if (step.label.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(step.label, style: const TextStyle(color: Colors.white70, fontSize: 10)),
                      ],
                      const SizedBox(height: 3),
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.nfc, size: 10,
                            color: step.nfcTagIds.isNotEmpty ? Colors.lightBlueAccent : Colors.grey),
                        const SizedBox(width: 2),
                        Text(_stepTagSummary(step),
                            style: TextStyle(fontSize: 9,
                                color: step.nfcTagIds.isNotEmpty ? Colors.lightBlueAccent : Colors.grey)),
                      ]),
                    ]),
                  );
                }),
              ),
            ),
          const SizedBox(height: 10),
          Row(children: [
            Text(daysText, style: const TextStyle(color: Colors.white38, fontSize: 11)),
            const Spacer(),
            if (countdown.isNotEmpty)
              Text(countdown, style: const TextStyle(color: Colors.white38, fontSize: 11)),
          ]),
        ]),
      ),
    );
  }
}

// ─── 알람 목록 아이템 ───────────────────────────────────────────────────────
class _AlarmListItem extends StatelessWidget {
  final AlarmData alarm;
  final List<String> dayLabels;
  final String countdownText, nfcTagName;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;

  const _AlarmListItem({
    required this.alarm, required this.dayLabels, required this.countdownText,
    required this.nfcTagName, required this.onTap, required this.onToggle,
  });

  static const _soundIcons = {
    'alarm': Icons.alarm, 'notification': Icons.notifications,
    'ringtone': Icons.music_note, 'silent': Icons.volume_off,
  };

  @override
  Widget build(BuildContext context) {
    final h = alarm.hour.toString().padLeft(2, '0');
    final m = alarm.minute.toString().padLeft(2, '0');
    final daysText = alarm.days.isEmpty ? '반복 없음' : alarm.days.map((d) => dayLabels[d - 1]).join(' ');
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
        decoration: BoxDecoration(color: const Color(0xFF16213E),
            borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white12)),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$h:$m', style: TextStyle(
                color: alarm.enabled ? Colors.white : Colors.grey,
                fontSize: 40, fontWeight: FontWeight.bold, letterSpacing: 2)),
            const SizedBox(height: 4),
            Text(daysText, style: TextStyle(
                color: alarm.enabled ? Colors.white70 : Colors.grey, fontSize: 13)),
            const SizedBox(height: 4),
            Row(children: [
              Icon(Icons.nfc, size: 12,
                  color: alarm.nfcTagIds.isNotEmpty ? Colors.lightBlueAccent : Colors.grey),
              const SizedBox(width: 3),
              Text(nfcTagName, style: TextStyle(
                  color: alarm.nfcTagIds.isNotEmpty ? Colors.lightBlueAccent : Colors.grey,
                  fontSize: 11)),
              const SizedBox(width: 10),
              Icon(_soundIcons[alarm.soundType] ?? Icons.alarm, size: 12, color: Colors.grey),
              const SizedBox(width: 3),
              Text('${(alarm.volume * 100).round()}%',
                  style: const TextStyle(color: Colors.grey, fontSize: 11)),
              if (countdownText.isNotEmpty) ...[
                const SizedBox(width: 10),
                Text(countdownText, style: const TextStyle(color: Colors.white38, fontSize: 11)),
              ],
            ]),
          ])),
          Switch(value: alarm.enabled, onChanged: onToggle, activeColor: Colors.green),
        ]),
      ),
    );
  }
}

// ─── 알람 편집 / 생성 화면 ──────────────────────────────────────────────────
class AlarmEditScreen extends StatefulWidget {
  final AlarmData? alarm;
  final List<NfcTagData> nfcTags;
  final Future<void> Function(int, int, List<int>, List<int>, String, double) onSave;
  final Future<void> Function()? onDelete;

  const AlarmEditScreen({super.key, required this.alarm, required this.nfcTags,
    required this.onSave, this.onDelete});

  @override
  State<AlarmEditScreen> createState() => _AlarmEditScreenState();
}

class _AlarmEditScreenState extends State<AlarmEditScreen> {
  static const _dayLabels = ['월', '화', '수', '목', '금', '토', '일'];
  late int _hour, _minute;
  late List<int> _days, _nfcTagIds;
  late String _soundType;
  late double _volume;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.alarm != null) {
      _hour = widget.alarm!.hour; _minute = widget.alarm!.minute;
      _days = List.from(widget.alarm!.days); _nfcTagIds = List.from(widget.alarm!.nfcTagIds);
      _soundType = widget.alarm!.soundType; _volume = widget.alarm!.volume;
    } else {
      final now = TimeOfDay.now();
      _hour = now.hour; _minute = now.minute;
      _days = [1, 2, 3, 4, 5]; _nfcTagIds = [];
      _soundType = 'alarm'; _volume = 1.0;
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context,
        initialTime: TimeOfDay(hour: _hour, minute: _minute));
    if (picked != null) setState(() { _hour = picked.hour; _minute = picked.minute; });
  }

  Future<void> _save() async {
    if (_days.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('요일을 하나 이상 선택하세요'), duration: Duration(seconds: 2)));
      return;
    }
    setState(() => _saving = true);
    await widget.onSave(_hour, _minute, _days, _nfcTagIds, _soundType, _volume);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _confirmDelete() async {
    final confirm = await showDialog<bool>(context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('알람 삭제'), content: const Text('이 알람을 삭제할까요?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('삭제', style: TextStyle(color: Colors.red))),
        ],
      ));
    if (confirm == true) { await widget.onDelete!(); if (mounted) Navigator.pop(context); }
  }

  @override
  Widget build(BuildContext context) {
    final h = _hour.toString().padLeft(2, '0');
    final m = _minute.toString().padLeft(2, '0');
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(widget.alarm == null ? '새 알람' : '알람 편집',
            style: const TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [if (widget.onDelete != null)
          IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: _confirmDelete)],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          GestureDetector(onTap: _pickTime,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 28),
              decoration: BoxDecoration(color: const Color(0xFF16213E),
                  borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white12)),
              child: Center(child: Text('$h:$m', style: const TextStyle(
                  color: Colors.white, fontSize: 72, fontWeight: FontWeight.bold, letterSpacing: 4))),
            )),
          const SizedBox(height: 6),
          const Center(child: Text('탭하여 시간 변경', style: TextStyle(color: Colors.grey, fontSize: 12))),
          const SizedBox(height: 28),
          const Text('반복 요일', style: TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8,
            children: List.generate(7, (i) {
              final day = i + 1; final selected = _days.contains(day);
              return FilterChip(
                label: Text(_dayLabels[i]), selected: selected,
                onSelected: (v) => setState(() { if (v) { _days.add(day); _days.sort(); } else _days.remove(day); }),
                selectedColor: const Color(0xFF0F3460), checkmarkColor: Colors.white,
                labelStyle: TextStyle(color: selected ? Colors.white : Colors.grey),
                backgroundColor: const Color(0xFF1A1A2E),
                side: BorderSide(color: selected ? Colors.blue : Colors.grey),
              );
            }),
          ),
          const SizedBox(height: 28),
          const Text('알람 소리', style: TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            style: SegmentedButton.styleFrom(backgroundColor: const Color(0xFF16213E),
                selectedBackgroundColor: const Color(0xFF0F3460),
                foregroundColor: Colors.grey, selectedForegroundColor: Colors.white),
            segments: const [
              ButtonSegment(value: 'alarm', label: Text('알람'), icon: Icon(Icons.alarm, size: 16)),
              ButtonSegment(value: 'notification', label: Text('알림'), icon: Icon(Icons.notifications, size: 16)),
              ButtonSegment(value: 'ringtone', label: Text('벨소리'), icon: Icon(Icons.music_note, size: 16)),
              ButtonSegment(value: 'silent', label: Text('무음'), icon: Icon(Icons.volume_off, size: 16)),
            ],
            selected: {_soundType},
            onSelectionChanged: (s) => setState(() => _soundType = s.first),
          ),
          const SizedBox(height: 28),
          Row(children: [
            const Text('볼륨', style: TextStyle(color: Colors.grey, fontSize: 13)),
            const Spacer(),
            Text('${(_volume * 100).round()}%', style: const TextStyle(color: Colors.white, fontSize: 13)),
          ]),
          Slider(value: _volume, min: 0.1, max: 1.0, divisions: 9,
            activeColor: const Color(0xFF0F3460),
            onChanged: _soundType == 'silent' ? null : (v) => setState(() => _volume = v)),
          const SizedBox(height: 28),
          const Text('NFC 태그 (알람 해제용 — 하나라도 태그되면 해제)',
              style: TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 12),
          if (widget.nfcTags.isEmpty)
            const Text('등록된 NFC 태그가 없습니다. 메뉴 > NFC 태그 관리에서 먼저 등록하세요.',
                style: TextStyle(color: Colors.orange, fontSize: 11))
          else
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilterChip(
                label: const Text('아무 태그나'),
                selected: _nfcTagIds.isEmpty,
                onSelected: (v) { if (v) setState(() => _nfcTagIds.clear()); },
                selectedColor: const Color(0xFF0F3460), checkmarkColor: Colors.white,
                labelStyle: TextStyle(color: _nfcTagIds.isEmpty ? Colors.white : Colors.grey),
                backgroundColor: const Color(0xFF1A1A2E),
                side: BorderSide(color: _nfcTagIds.isEmpty ? Colors.blue : Colors.grey),
              ),
              ...widget.nfcTags.map((t) {
                final sel = _nfcTagIds.contains(t.id);
                return FilterChip(
                  label: Text(t.name), selected: sel,
                  onSelected: (v) => setState(() { if (v) _nfcTagIds.add(t.id); else _nfcTagIds.remove(t.id); }),
                  selectedColor: const Color(0xFF0F3460), checkmarkColor: Colors.white,
                  labelStyle: TextStyle(color: sel ? Colors.white : Colors.grey),
                  backgroundColor: const Color(0xFF1A1A2E),
                  side: BorderSide(color: sel ? Colors.blue : Colors.grey),
                );
              }),
            ]),
          const SizedBox(height: 100),
        ]),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saving ? null : _save,
        backgroundColor: const Color(0xFF0F3460),
        icon: _saving ? const SizedBox(width: 20, height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.check, color: Colors.white),
        label: const Text('저장', style: TextStyle(color: Colors.white)),
      ),
    );
  }
}

// ─── 알람 체인 편집 / 생성 화면 ─────────────────────────────────────────────
class AlarmChainEditScreen extends StatefulWidget {
  final AlarmChain? chain;
  final List<NfcTagData> nfcTags;
  final Future<void> Function(String name, List<int> days, List<ChainStep> steps) onSave;
  final Future<void> Function()? onDelete;

  const AlarmChainEditScreen({super.key, required this.chain, required this.nfcTags,
    required this.onSave, this.onDelete});

  @override
  State<AlarmChainEditScreen> createState() => _AlarmChainEditScreenState();
}

class _AlarmChainEditScreenState extends State<AlarmChainEditScreen> {
  static const _dayLabels = ['월', '화', '수', '목', '금', '토', '일'];
  late TextEditingController _nameCtrl;
  late List<int> _days;
  late List<ChainStep> _steps;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.chain?.name ?? '');
    _days = List.from(widget.chain?.days ?? [1, 2, 3, 4, 5]);
    _steps = List.from(widget.chain?.steps ?? []);
  }

  @override
  void dispose() { _nameCtrl.dispose(); super.dispose(); }

  Future<void> _openStepEdit(ChainStep? step, int? index) async {
    // 현재 단계를 제외한 다른 단계들이 사용 중인 태그 ID
    final usedTagIds = <int>{};
    for (int i = 0; i < _steps.length; i++) {
      if (i != index) usedTagIds.addAll(_steps[i].nfcTagIds);
    }
    final result = await Navigator.push<ChainStep>(context, MaterialPageRoute(
      builder: (_) => ChainStepEditScreen(
          step: step, nfcTags: widget.nfcTags, excludedTagIds: usedTagIds),
    ));
    if (result != null) {
      setState(() {
        if (index == null) _steps.add(result);
        else _steps[index] = result;
      });
    }
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('체인 이름을 입력하세요')));
      return;
    }
    if (_days.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('요일을 하나 이상 선택하세요')));
      return;
    }
    if (_steps.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('단계를 하나 이상 추가하세요')));
      return;
    }
    setState(() => _saving = true);
    await widget.onSave(_nameCtrl.text.trim(), _days, _steps);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _confirmDelete() async {
    final confirm = await showDialog<bool>(context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('체인 삭제'),
        content: const Text('이 체인을 삭제할까요?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('삭제', style: TextStyle(color: Colors.red))),
        ],
      ));
    if (confirm == true) { await widget.onDelete!(); if (mounted) Navigator.pop(context); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(widget.chain == null ? '새 체인' : '체인 편집',
            style: const TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [if (widget.onDelete != null)
          IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: _confirmDelete)],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: TextField(
            controller: _nameCtrl,
            style: const TextStyle(color: Colors.white, fontSize: 18),
            decoration: InputDecoration(
              labelText: '체인 이름 (예: 아침 루틴)',
              labelStyle: const TextStyle(color: Colors.grey),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white24)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.blue)),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('반복 요일', style: TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8,
              children: List.generate(7, (i) {
                final day = i + 1; final selected = _days.contains(day);
                return FilterChip(
                  label: Text(_dayLabels[i]), selected: selected,
                  onSelected: (v) => setState(() {
                    if (v) { _days.add(day); _days.sort(); } else _days.remove(day);
                  }),
                  selectedColor: const Color(0xFF0F3460), checkmarkColor: Colors.white,
                  labelStyle: TextStyle(color: selected ? Colors.white : Colors.grey),
                  backgroundColor: const Color(0xFF1A1A2E),
                  side: BorderSide(color: selected ? Colors.blue : Colors.grey),
                );
              }),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(children: [
            const Text('단계', style: TextStyle(color: Colors.grey, fontSize: 13)),
            const Spacer(),
            TextButton.icon(
              onPressed: () => _openStepEdit(null, null),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('단계 추가'),
              style: TextButton.styleFrom(foregroundColor: Colors.blue),
            ),
          ]),
        ),
        Expanded(
          child: _steps.isEmpty
              ? const Center(child: Text('단계를 추가하세요', style: TextStyle(color: Colors.grey)))
              : ReorderableListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                  onReorder: (o, n) {
                    setState(() {
                      if (n > o) n--;
                      final item = _steps.removeAt(o);
                      _steps.insert(n, item);
                    });
                  },
                  children: List.generate(_steps.length, (i) {
                    final step = _steps[i];
                    final h = step.hour.toString().padLeft(2, '0');
                    final m = step.minute.toString().padLeft(2, '0');
                    return Padding(
                      key: ValueKey('step_$i'),
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Container(
                        decoration: BoxDecoration(color: const Color(0xFF16213E),
                            borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white12)),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          leading: Container(
                            width: 28, height: 28,
                            decoration: const BoxDecoration(color: Color(0xFF0F3460), shape: BoxShape.circle),
                            child: Center(child: Text('${i + 1}', style: const TextStyle(
                                color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))),
                          ),
                          title: Text('$h:$m${step.label.isNotEmpty ? "  ·  ${step.label}" : ""}',
                              style: const TextStyle(color: Colors.white, fontSize: 14)),
                          subtitle: Text(
                            step.nfcTagIds.isEmpty ? '아무 태그나' : '태그 ${step.nfcTagIds.length}개',
                            style: const TextStyle(color: Colors.white38, fontSize: 11)),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            IconButton(icon: const Icon(Icons.edit_outlined, color: Colors.white54, size: 18),
                              onPressed: () => _openStepEdit(step, i)),
                            IconButton(icon: const Icon(Icons.close, color: Colors.red, size: 18),
                              onPressed: () => setState(() => _steps.removeAt(i))),
                            const Icon(Icons.drag_handle, color: Colors.white38, size: 20),
                          ]),
                        ),
                      ),
                    );
                  }),
                ),
        ),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saving ? null : _save,
        backgroundColor: const Color(0xFF0F3460),
        icon: _saving ? const SizedBox(width: 20, height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.check, color: Colors.white),
        label: const Text('저장', style: TextStyle(color: Colors.white)),
      ),
    );
  }
}

// ─── 체인 단계 편집 화면 ─────────────────────────────────────────────────────
class ChainStepEditScreen extends StatefulWidget {
  final ChainStep? step;
  final List<NfcTagData> nfcTags;
  final Set<int> excludedTagIds;
  const ChainStepEditScreen(
      {super.key, required this.step, required this.nfcTags, this.excludedTagIds = const {}});

  @override
  State<ChainStepEditScreen> createState() => _ChainStepEditScreenState();
}

class _ChainStepEditScreenState extends State<ChainStepEditScreen> {
  late int _hour, _minute;
  late TextEditingController _labelCtrl;
  late List<int> _nfcTagIds;
  late String _soundType;
  late double _volume;

  @override
  void initState() {
    super.initState();
    if (widget.step != null) {
      _hour = widget.step!.hour; _minute = widget.step!.minute;
      _labelCtrl = TextEditingController(text: widget.step!.label);
      _nfcTagIds = List.from(widget.step!.nfcTagIds);
      _soundType = widget.step!.soundType; _volume = widget.step!.volume;
    } else {
      final now = TimeOfDay.now(); _hour = now.hour; _minute = now.minute;
      _labelCtrl = TextEditingController(); _nfcTagIds = [];
      _soundType = 'alarm'; _volume = 1.0;
    }
  }

  @override
  void dispose() { _labelCtrl.dispose(); super.dispose(); }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context,
        initialTime: TimeOfDay(hour: _hour, minute: _minute));
    if (picked != null) setState(() { _hour = picked.hour; _minute = picked.minute; });
  }

  void _save() {
    Navigator.pop(context, ChainStep(
      hour: _hour, minute: _minute, label: _labelCtrl.text.trim(),
      nfcTagIds: _nfcTagIds, soundType: _soundType, volume: _volume,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final h = _hour.toString().padLeft(2, '0');
    final m = _minute.toString().padLeft(2, '0');
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(widget.step == null ? '새 단계' : '단계 편집',
            style: const TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          GestureDetector(onTap: _pickTime,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 28),
              decoration: BoxDecoration(color: const Color(0xFF16213E),
                  borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white12)),
              child: Center(child: Text('$h:$m', style: const TextStyle(
                  color: Colors.white, fontSize: 72, fontWeight: FontWeight.bold, letterSpacing: 4))),
            )),
          const SizedBox(height: 6),
          const Center(child: Text('탭하여 시간 변경', style: TextStyle(color: Colors.grey, fontSize: 12))),
          const SizedBox(height: 24),
          TextField(
            controller: _labelCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: '단계 이름 (선택, 예: 기상, 헬스장)',
              labelStyle: const TextStyle(color: Colors.grey),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white24)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.blue)),
            ),
          ),
          const SizedBox(height: 28),
          const Text('알람 소리', style: TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            style: SegmentedButton.styleFrom(backgroundColor: const Color(0xFF16213E),
                selectedBackgroundColor: const Color(0xFF0F3460),
                foregroundColor: Colors.grey, selectedForegroundColor: Colors.white),
            segments: const [
              ButtonSegment(value: 'alarm', label: Text('알람'), icon: Icon(Icons.alarm, size: 16)),
              ButtonSegment(value: 'notification', label: Text('알림'), icon: Icon(Icons.notifications, size: 16)),
              ButtonSegment(value: 'ringtone', label: Text('벨소리'), icon: Icon(Icons.music_note, size: 16)),
              ButtonSegment(value: 'silent', label: Text('무음'), icon: Icon(Icons.volume_off, size: 16)),
            ],
            selected: {_soundType},
            onSelectionChanged: (s) => setState(() => _soundType = s.first),
          ),
          const SizedBox(height: 28),
          Row(children: [
            const Text('볼륨', style: TextStyle(color: Colors.grey, fontSize: 13)),
            const Spacer(),
            Text('${(_volume * 100).round()}%', style: const TextStyle(color: Colors.white, fontSize: 13)),
          ]),
          Slider(value: _volume, min: 0.1, max: 1.0, divisions: 9,
            activeColor: const Color(0xFF0F3460),
            onChanged: _soundType == 'silent' ? null : (v) => setState(() => _volume = v)),
          const SizedBox(height: 28),
          const Text('NFC 태그 (하나라도 태그되면 해제)',
              style: TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 12),
          if (widget.nfcTags.isEmpty)
            const Text('등록된 NFC 태그가 없습니다. 메뉴 > NFC 태그 관리에서 먼저 등록하세요.',
                style: TextStyle(color: Colors.orange, fontSize: 11))
          else
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilterChip(
                label: const Text('아무 태그나'),
                selected: _nfcTagIds.isEmpty,
                onSelected: (v) { if (v) setState(() => _nfcTagIds.clear()); },
                selectedColor: const Color(0xFF0F3460), checkmarkColor: Colors.white,
                labelStyle: TextStyle(color: _nfcTagIds.isEmpty ? Colors.white : Colors.grey),
                backgroundColor: const Color(0xFF1A1A2E),
                side: BorderSide(color: _nfcTagIds.isEmpty ? Colors.blue : Colors.grey),
              ),
              ...widget.nfcTags.map((t) {
                final sel = _nfcTagIds.contains(t.id);
                final excluded = widget.excludedTagIds.contains(t.id);
                return FilterChip(
                  label: Text(excluded ? '${t.name} (사용 중)' : t.name),
                  selected: sel,
                  onSelected: excluded ? null
                      : (v) => setState(() { if (v) _nfcTagIds.add(t.id); else _nfcTagIds.remove(t.id); }),
                  selectedColor: const Color(0xFF0F3460), checkmarkColor: Colors.white,
                  labelStyle: TextStyle(color: excluded ? Colors.grey.shade700 : sel ? Colors.white : Colors.grey),
                  backgroundColor: const Color(0xFF1A1A2E),
                  side: BorderSide(color: excluded ? Colors.grey.shade800 : sel ? Colors.blue : Colors.grey),
                );
              }),
            ]),
          const SizedBox(height: 100),
        ]),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _save,
        backgroundColor: const Color(0xFF0F3460),
        icon: const Icon(Icons.check, color: Colors.white),
        label: const Text('저장', style: TextStyle(color: Colors.white)),
      ),
    );
  }
}

// ─── 체인 체크인 다이얼로그 ────────────────────────────────────────────────
class _ChainCheckInDialog extends StatefulWidget {
  final AlarmChain chain;
  final List<NfcTagData> nfcTags;
  final Future<void> Function(List<int> stepIndices) onSkip;

  const _ChainCheckInDialog({required this.chain, required this.nfcTags, required this.onSkip});

  @override
  State<_ChainCheckInDialog> createState() => _ChainCheckInDialogState();
}

class _ChainCheckInDialogState extends State<_ChainCheckInDialog> {
  String _status = 'scanning';
  String _errorMsg = '';
  List<int> _toSkipIndices = [];

  @override
  void initState() { super.initState(); _startScan(); }

  Future<void> _startScan() async {
    setState(() { _status = 'scanning'; _errorMsg = ''; _toSkipIndices = []; });
    NfcManager.instance.startSession(onDiscovered: (NfcTag tag) async {
      final data = tag.data;
      List<int>? id;
      for (final key in ['nfca', 'nfcb', 'nfcf', 'nfcv']) {
        if (data[key] != null) { id = List<int>.from(data[key]['identifier']); break; }
      }
      await NfcManager.instance.stopSession();
      if (id == null || !mounted) return;
      final uid = id.map((e) => e.toRadixString(16).padLeft(2, '0')).join(':');

      int? scannedStep;
      for (int i = 1; i < widget.chain.steps.length; i++) {
        final step = widget.chain.steps[i];
        for (final tagId in step.nfcTagIds) {
          for (final t in widget.nfcTags) {
            if (t.id == tagId && t.uid == uid) { scannedStep = i; break; }
          }
          if (scannedStep != null) break;
        }
        if (scannedStep != null) break;
      }

      if (scannedStep == null) {
        setState(() { _status = 'error'; _errorMsg = '체인의 2단계 이후 태그가 아닙니다\n1단계 태그는 체크인에 사용할 수 없습니다'; });
        return;
      }
      setState(() { _toSkipIndices = List.generate(scannedStep!, (i) => i); _status = 'confirm'; });
    });
  }

  @override
  void dispose() { NfcManager.instance.stopSession(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF16213E),
      title: Text('"${widget.chain.name}" 체크인', style: const TextStyle(color: Colors.white)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 8),
        if (_status == 'scanning') ...[
          const CircularProgressIndicator(),
          const SizedBox(height: 20),
          const Text('태그를 폰에 갖다 대세요', style: TextStyle(color: Colors.white70, fontSize: 15)),
          const SizedBox(height: 4),
          const Text('(2단계 이후 단계의 태그)', style: TextStyle(color: Colors.white38, fontSize: 12)),
        ] else if (_status == 'confirm') ...[
          const Icon(Icons.nfc, color: Colors.blue, size: 48),
          const SizedBox(height: 12),
          Text('${_toSkipIndices.length}개 단계를 오늘 건너뜁니다',
              style: const TextStyle(color: Colors.white, fontSize: 15)),
          const SizedBox(height: 10),
          ..._toSkipIndices.map((i) {
            final step = widget.chain.steps[i];
            final h = step.hour.toString().padLeft(2, '0');
            final m = step.minute.toString().padLeft(2, '0');
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(children: [
                const Icon(Icons.skip_next, color: Colors.orange, size: 16),
                const SizedBox(width: 6),
                Text('$h:$m${step.label.isNotEmpty ? " ${step.label}" : ""} 건너뜀',
                    style: const TextStyle(color: Colors.orange, fontSize: 13)),
              ]),
            );
          }),
        ] else if (_status == 'done') ...[
          const Icon(Icons.check_circle, color: Colors.green, size: 64),
          const SizedBox(height: 12),
          const Text('건너뜀 완료', style: TextStyle(color: Colors.green, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('오늘은 해당 단계 알람이 울리지 않습니다',
              style: TextStyle(color: Colors.white54, fontSize: 12)),
        ] else ...[
          const Icon(Icons.error_outline, color: Colors.red, size: 56),
          const SizedBox(height: 12),
          Text(_errorMsg, textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red, fontSize: 13)),
        ],
      ]),
      actions: [
        if (_status == 'confirm') ...[
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0F3460)),
            onPressed: () async {
              await widget.onSkip(_toSkipIndices);
              if (mounted) setState(() => _status = 'done');
            },
            child: Text('${_toSkipIndices.length}개 건너뜀'),
          ),
        ] else if (_status == 'error') ...[
          TextButton(onPressed: _startScan, child: const Text('다시 시도')),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('닫기')),
        ] else
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_status == 'done' ? '완료' : '취소'),
          ),
      ],
    );
  }
}

// ─── NFC 태그 관리 화면 ─────────────────────────────────────────────────────
class NfcTagListScreen extends StatefulWidget {
  final List<NfcTagData> nfcTags;
  final int nextId;
  final Future<void> Function(List<NfcTagData> tags, int nextId) onChanged;
  const NfcTagListScreen({super.key, required this.nfcTags, required this.nextId, required this.onChanged});

  @override
  State<NfcTagListScreen> createState() => _NfcTagListScreenState();
}

class _NfcTagListScreenState extends State<NfcTagListScreen> {
  late List<NfcTagData> _tags;
  late int _nextId;

  @override
  void initState() { super.initState(); _tags = List.from(widget.nfcTags); _nextId = widget.nextId; }

  Future<void> _save() async => widget.onChanged(_tags, _nextId);

  Future<void> _openSheet(NfcTagData? tag) async {
    await showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: const Color(0xFF16213E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _NfcTagEditSheet(
        tag: tag,
        onSave: (name, uid) async {
          if (tag == null) {
            setState(() => _tags.add(NfcTagData(id: _nextId++, name: name, uid: uid)));
          } else {
            final idx = _tags.indexWhere((t) => t.id == tag.id);
            if (idx != -1) setState(() => _tags[idx] = tag.copyWith(name: name, uid: uid));
          }
          await _save();
          if (mounted) Navigator.pop(context);
        },
      ),
    );
  }

  Future<void> _testTag(NfcTagData tag) async {
    final isAvailable = await NfcManager.instance.isAvailable();
    if (!isAvailable) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('NFC를 사용할 수 없습니다')));
      return;
    }
    if (!mounted) return;
    await showDialog(context: context, builder: (_) => _NfcTagTestDialog(tag: tag));
  }

  Future<void> _delete(NfcTagData tag) async {
    final confirm = await showDialog<bool>(context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('태그 삭제'), content: Text('"${tag.name}" 태그를 삭제할까요?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('삭제', style: TextStyle(color: Colors.red))),
        ],
      ));
    if (confirm == true) { setState(() => _tags.removeWhere((t) => t.id == tag.id)); await _save(); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(backgroundColor: Colors.transparent,
        title: const Text('NFC 태그 관리', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white)),
      body: _tags.isEmpty
          ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.nfc, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text('등록된 태그가 없습니다', style: TextStyle(color: Colors.grey, fontSize: 16)),
              SizedBox(height: 8),
              Text('+ 버튼으로 태그를 추가하세요', style: TextStyle(color: Colors.grey, fontSize: 13)),
            ]))
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
              itemCount: _tags.length,
              itemBuilder: (_, i) {
                final tag = _tags[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
                    decoration: BoxDecoration(color: const Color(0xFF16213E),
                        borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white12)),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      leading: const Icon(Icons.nfc, color: Colors.lightBlueAccent),
                      title: Text(tag.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      subtitle: Text(tag.uid, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(icon: const Icon(Icons.sensors, color: Colors.greenAccent, size: 20),
                          tooltip: '태그 테스트', onPressed: () => _testTag(tag)),
                        IconButton(icon: const Icon(Icons.edit_outlined, color: Colors.white54, size: 20),
                          onPressed: () => _openSheet(tag)),
                        IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                          onPressed: () => _delete(tag)),
                      ]),
                    ),
                  ),
                );
              }),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openSheet(null),
        backgroundColor: const Color(0xFF0F3460),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}

// ─── NFC 태그 테스트 다이얼로그 ────────────────────────────────────────────────
class _NfcTagTestDialog extends StatefulWidget {
  final NfcTagData tag;
  const _NfcTagTestDialog({required this.tag});
  @override
  State<_NfcTagTestDialog> createState() => _NfcTagTestDialogState();
}

class _NfcTagTestDialogState extends State<_NfcTagTestDialog> {
  String _status = 'scanning';
  String? _scannedUid;

  @override
  void initState() { super.initState(); _startScan(); }

  Future<void> _startScan() async {
    NfcManager.instance.startSession(onDiscovered: (NfcTag nfcTag) async {
      final data = nfcTag.data;
      List<int>? id;
      for (final key in ['nfca', 'nfcb', 'nfcf', 'nfcv']) {
        if (data[key] != null) { id = List<int>.from(data[key]['identifier']); break; }
      }
      await NfcManager.instance.stopSession();
      if (id != null && mounted) {
        final uid = id.map((e) => e.toRadixString(16).padLeft(2, '0')).join(':');
        setState(() { _scannedUid = uid; _status = uid == widget.tag.uid ? 'matched' : 'mismatch'; });
      }
    });
  }

  @override
  void dispose() { NfcManager.instance.stopSession(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF16213E),
      title: Text('"${widget.tag.name}" 테스트', style: const TextStyle(color: Colors.white)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 8),
        if (_status == 'scanning') ...[
          const CircularProgressIndicator(),
          const SizedBox(height: 20),
          const Text('태그를 폰에 갖다 대세요', style: TextStyle(color: Colors.white70, fontSize: 15)),
          const SizedBox(height: 8),
        ] else if (_status == 'matched') ...[
          const Icon(Icons.check_circle, color: Colors.green, size: 72),
          const SizedBox(height: 12),
          const Text('일치!', style: TextStyle(color: Colors.green, fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(_scannedUid ?? '', style: const TextStyle(color: Colors.grey, fontSize: 11)),
        ] else ...[
          const Icon(Icons.cancel, color: Colors.red, size: 72),
          const SizedBox(height: 12),
          const Text('불일치', style: TextStyle(color: Colors.red, fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('스캔: $_scannedUid', style: const TextStyle(color: Colors.grey, fontSize: 11)),
          const SizedBox(height: 4),
          Text('등록: ${widget.tag.uid}', style: const TextStyle(color: Colors.grey, fontSize: 11)),
        ],
      ]),
      actions: [
        if (_status != 'scanning')
          TextButton(
            onPressed: () { setState(() { _status = 'scanning'; _scannedUid = null; }); _startScan(); },
            child: const Text('다시 테스트')),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('닫기')),
      ],
    );
  }
}

class _NfcTagEditSheet extends StatefulWidget {
  final NfcTagData? tag;
  final Future<void> Function(String name, String uid) onSave;
  const _NfcTagEditSheet({required this.tag, required this.onSave});
  @override
  State<_NfcTagEditSheet> createState() => _NfcTagEditSheetState();
}

class _NfcTagEditSheetState extends State<_NfcTagEditSheet> {
  late TextEditingController _nameCtrl;
  String? _scannedUid;
  bool _scanning = false, _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.tag?.name ?? '');
    _scannedUid = widget.tag?.uid;
  }

  @override
  void dispose() { _nameCtrl.dispose(); NfcManager.instance.stopSession(); super.dispose(); }

  Future<void> _startScan() async {
    if (!await NfcManager.instance.isAvailable()) return;
    setState(() => _scanning = true);
    NfcManager.instance.startSession(onDiscovered: (NfcTag tag) async {
      final data = tag.data;
      List<int>? id;
      for (final key in ['nfca', 'nfcb', 'nfcf', 'nfcv']) {
        if (data[key] != null) { id = List<int>.from(data[key]['identifier']); break; }
      }
      NfcManager.instance.stopSession();
      if (id != null && mounted) {
        setState(() {
          _scannedUid = id!.map((e) => e.toRadixString(16).padLeft(2, '0')).join(':');
          _scanning = false;
        });
      }
    });
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('태그 이름을 입력하세요')));
      return;
    }
    if (_scannedUid == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('NFC 태그를 스캔하세요')));
      return;
    }
    setState(() => _saving = true);
    await widget.onSave(_nameCtrl.text.trim(), _scannedUid!);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 24, right: 24, top: 24,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.tag == null ? 'NFC 태그 추가' : 'NFC 태그 편집',
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          TextField(controller: _nameCtrl, style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: '태그 이름 (예: 집 문앞)', labelStyle: const TextStyle(color: Colors.grey),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Colors.white24)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Colors.blue)),
            )),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _scanning ? null : _startScan,
            icon: _scanning ? const SizedBox(width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.nfc),
            label: Text(_scanning ? '태그를 갖다 대세요...' : _scannedUid == null ? 'NFC 스캔' : '다시 스캔'),
            style: OutlinedButton.styleFrom(foregroundColor: Colors.lightBlueAccent,
                side: const BorderSide(color: Colors.lightBlueAccent),
                padding: const EdgeInsets.symmetric(vertical: 14)),
          ),
          if (_scannedUid != null) ...[
            const SizedBox(height: 8),
            Text('스캔됨: $_scannedUid',
                style: const TextStyle(color: Colors.green, fontSize: 12), textAlign: TextAlign.center),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0F3460),
                padding: const EdgeInsets.symmetric(vertical: 14)),
            child: _saving ? const SizedBox(width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('저장', style: TextStyle(color: Colors.white)),
          ),
        ]),
    );
  }
}

// ─── 알람 화면 ──────────────────────────────────────────────────────────────
class AlarmRingingScreen extends StatefulWidget {
  final Future<void> Function(Function(bool)) onNfcScan;
  final VoidCallback onDismiss;
  const AlarmRingingScreen({super.key, required this.onNfcScan, required this.onDismiss});
  @override
  State<AlarmRingingScreen> createState() => _AlarmRingingScreenState();
}

class _AlarmRingingScreenState extends State<AlarmRingingScreen> with TickerProviderStateMixin {
  bool _isScanning = false;
  String _message = '다른 방으로 이동해서\nNFC 태그를 스캔하세요!';
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  int _autoOffRemaining = 300;
  bool _isMuted = false;
  int _muteRemaining = 0;
  Timer? _ticker;

  void _onServiceData(Object data) {
    if (data.toString() == 'alarm_auto_off' && mounted) {
      widget.onDismiss(); Navigator.of(context).pop();
    }
  }

  @override
  void initState() {
    super.initState();
    FlutterForegroundTask.addTaskDataCallback(_onServiceData);
    _pulseController = AnimationController(vsync: this, duration: const Duration(seconds: 1))
      ..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
        CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_autoOffRemaining > 0) _autoOffRemaining--;
        if (_isMuted && _muteRemaining > 0) {
          _muteRemaining--;
          if (_muteRemaining == 0) { _isMuted = false; FlutterForegroundTask.sendDataToTask('resume_sound'); }
        }
      });
    });
    _checkNfcStatus();
  }

  Future<void> _checkNfcStatus() async {
    final isAvailable = await NfcManager.instance.isAvailable();
    if (!isAvailable && mounted) {
      showDialog(context: context, barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('NFC가 꺼져 있습니다'),
          content: const Text('알람을 끄려면 NFC가 필요합니다.\nNFC 설정을 열어 활성화하세요.'),
          actions: [TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              const AndroidIntent(action: 'android.settings.NFC_SETTINGS').launch();
            },
            child: const Text('NFC 설정 열기'))],
        ));
    }
  }

  @override
  void dispose() {
    FlutterForegroundTask.removeTaskDataCallback(_onServiceData);
    _ticker?.cancel(); _pulseController.dispose();
    NfcManager.instance.stopSession(); super.dispose();
  }

  void _cancelScan() {
    NfcManager.instance.stopSession();
    setState(() { _isScanning = false; _message = '다른 방으로 이동해서\nNFC 태그를 스캔하세요!'; });
  }

  void _toggleMute() {
    if (_isMuted) {
      setState(() { _isMuted = false; _muteRemaining = 0; });
      FlutterForegroundTask.sendDataToTask('resume_sound');
    } else {
      setState(() { _isMuted = true; _muteRemaining = 120; });
      FlutterForegroundTask.sendDataToTask('mute_temporary');
    }
  }

  Future<void> _startScan() async {
    setState(() { _isScanning = true; _message = '📱 태그에 갖다 대세요...'; });
    await widget.onNfcScan((bool success) {
      if (success) {
        widget.onDismiss();
        if (mounted) {
          setState(() => _message = '✅ 기상 성공!');
          Future.delayed(const Duration(milliseconds: 800), () { if (mounted) Navigator.of(context).pop(); });
        }
      } else {
        if (mounted) setState(() { _isScanning = false; _message = '❌ 잘못된 태그입니다!\n다시 시도하세요'; });
      }
    });
  }

  String get _autoOffText {
    final m = _autoOffRemaining ~/ 60;
    final s = (_autoOffRemaining % 60).toString().padLeft(2, '0');
    return '$m:$s 후 자동 꺼짐';
  }

  String get _muteButtonText {
    if (!_isMuted) return '🤫 잠깐만 조용히 (2분)';
    final m = _muteRemaining ~/ 60;
    final s = (_muteRemaining % 60).toString().padLeft(2, '0');
    return '🔊 $m:$s 후 소리 재시작 — 탭하여 지금 재시작';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF1A0000),
        body: SafeArea(
          child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            ScaleTransition(scale: _pulseAnimation,
              child: const Icon(Icons.alarm, size: 120, color: Colors.red)),
            const SizedBox(height: 24),
            const Text('⏰ 알람!',
                style: TextStyle(color: Colors.red, fontSize: 40, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(_message, textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 20, height: 1.5))),
            const SizedBox(height: 8),
            Text(_autoOffText, style: const TextStyle(color: Colors.white38, fontSize: 12)),
            const SizedBox(height: 32),
            GestureDetector(
              onTap: _isScanning ? null : _startScan,
              child: Container(
                width: 160, height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isScanning ? Colors.grey.withOpacity(0.3) : Colors.red.withOpacity(0.2),
                  border: Border.all(color: _isScanning ? Colors.grey : Colors.red, width: 3)),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  _isScanning ? const CircularProgressIndicator(color: Colors.white)
                      : const Icon(Icons.nfc, size: 64, color: Colors.red),
                  const SizedBox(height: 8),
                  Text(_isScanning ? '스캔 중...' : '탭해서 스캔',
                      style: const TextStyle(color: Colors.white, fontSize: 14)),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            if (_isScanning)
              TextButton.icon(
                onPressed: _cancelScan,
                icon: const Icon(Icons.close, size: 16, color: Colors.white38),
                label: const Text('스캔 취소', style: TextStyle(color: Colors.white38, fontSize: 13)))
            else const SizedBox(height: 32),
            TextButton(
              onPressed: _toggleMute,
              child: Text(_muteButtonText,
                  style: TextStyle(color: _isMuted ? Colors.orange : Colors.white54, fontSize: 13))),
          ])),
        ),
      ),
    );
  }
}
