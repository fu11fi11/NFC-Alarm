import 'dart:async';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../background/alarm_callback.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_constants.dart';
import '../../models/alarm_chain.dart';
import '../../models/alarm_data.dart';
import '../../providers/alarm_provider.dart';
import '../../providers/alarm_ringing_provider.dart';
import '../../providers/chain_provider.dart';
import '../../providers/nfc_tag_provider.dart';
import '../../services/alarm_service.dart';
import '../../services/app_logger.dart';
import '../../services/nfc_service.dart';
import '../../services/notification_service.dart';
import '../../services/storage_service.dart';
import '../alarm_edit_screen.dart';
import '../alarm_ringing_screen.dart';
import '../chain_edit_screen.dart';
import '../nfc_tag_list_screen.dart';
import 'widgets/alarm_list_item.dart';
import 'widgets/chain_card.dart';

// ─── 홈 화면 ──────────────────────────────────────────────────────────────────
class HomeScreen extends ConsumerStatefulWidget {
    const HomeScreen({super.key});
    @override
    ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
    bool _overlayGranted = true;
    bool _loading = true;
    Timer? _countdownTimer;

    void _onServiceData(Object data) {
        final msg = data.toString();
        if (msg == 'alarm_triggered' && mounted) {
            _handleAlarmTriggered();
        } else if (msg == 'alarm_auto_off' && mounted) {
            _dismissAlarm();
        }
    }

    @override
    void initState() {
        super.initState();
        appLog(LogTag.app, '앱 시작');
        FlutterForegroundTask.initCommunicationPort();
        FlutterForegroundTask.addTaskDataCallback(_onServiceData);
        _loadData();
        _checkOverlayPermission();
        _countdownTimer = Timer.periodic(
            const Duration(minutes: 1), (_) { if (mounted) setState(() {}); });
    }

    @override
    void dispose() {
        _countdownTimer?.cancel();
        FlutterForegroundTask.removeTaskDataCallback(_onServiceData);
        NfcService.instance.stopSession();
        super.dispose();
    }

    Future<void> _loadData() async {
        final data = await StorageService.instance.loadAll();
        if (!mounted) return;
        ref.read(nfcTagProvider.notifier).initialize(data.tags, data.nextTagId);
        ref.read(alarmProvider.notifier).initialize(data.alarms, data.nextAlarmId);
        ref.read(chainProvider.notifier).initialize(data.chains, data.nextChainId);
        setState(() => _loading = false);

        if (await FlutterForegroundTask.isRunningService && mounted) {
            await _handleAlarmTriggered();
        }
    }

    Future<void> _handleAlarmTriggered() async {
        final prefs = await SharedPreferences.getInstance();
        if (!mounted) return;
        final uids = prefs.getStringList('active_nfc_uids') ?? [];
        ref.read(alarmRingingProvider.notifier).setActive(uids);
        _pushAlarmScreen();
    }

    void _pushAlarmScreen() {
        Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => AlarmRingingScreen(onDismiss: _dismissAlarm),
        ));
    }

    void _dismissAlarm() {
        appLog(LogTag.alarm, '알람 수동 해제');
        ref.read(alarmRingingProvider.notifier).dismiss();
        NotificationService.instance.cancelAlarm();
        FlutterForegroundTask.stopService();
        SharedPreferences.getInstance().then((p) {
            p.remove('active_nfc_uids');
            p.remove('active_alarm_start_ms');
        });
        AppConstants.overlayChannel.invokeMethod('restoreAlarmVolume').catchError((_) {});
        final tags = ref.read(nfcTagProvider).tags;
        ref.read(alarmProvider.notifier).rescheduleAll(tags);
        ref.read(chainProvider.notifier).rescheduleAll(tags);
    }

    Future<void> _checkOverlayPermission() async {
        final granted = await AppConstants.overlayChannel
            .invokeMethod<bool>('canDrawOverlays') ?? false;
        if (mounted) setState(() => _overlayGranted = granted);
    }

    Future<void> _requestOverlayPermission() async {
        await const AndroidIntent(
            action: 'android.settings.action.MANAGE_OVERLAY_PERMISSION',
            data: 'package:${AppConstants.packageName}',
        ).launch();
        await Future.delayed(const Duration(seconds: 1));
        await _checkOverlayPermission();
    }

    // ─── 체인 유틸 ─────────────────────────────────────────────────────────────

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
        final next = chain.days
            .map((d) => AlarmService.instance.nextOccurrence(d, first.hour, first.minute))
            .reduce((a, b) => a.isBefore(b) ? a : b);
        final diff = next.difference(DateTime.now());
        return '${diff.inHours}시간 ${diff.inMinutes % 60}분 후 시작';
    }

    String _countdownFor(AlarmData alarm) {
        if (!alarm.enabled || alarm.days.isEmpty) return '';
        final next = alarm.days
            .map((d) => AlarmService.instance.nextOccurrence(d, alarm.hour, alarm.minute))
            .reduce((a, b) => a.isBefore(b) ? a : b);
        final diff = next.difference(DateTime.now());
        return '${diff.inHours}시간 ${diff.inMinutes % 60}분 후';
    }

    String _nfcTagNamesFor(AlarmData alarm) {
        final tags = ref.read(nfcTagProvider).tags;
        if (alarm.nfcTagIds.isEmpty) return '태그 미지정';
        final names = alarm.nfcTagIds.map((id) {
            for (final t in tags) { if (t.id == id) return t.name; }
            return null;
        }).whereType<String>().toList();
        if (names.isEmpty) return '태그 없음';
        if (names.length <= 2) return names.join(', ');
        return '${names.take(2).join(', ')} 외 ${names.length - 2}개';
    }

    // ─── 체인 체크인 ───────────────────────────────────────────────────────────

    Future<void> _startChainCheckIn(AlarmChain chain) async {
        final (canCheck, reason) = _checkInStatus(chain);
        if (!canCheck) { _showSnackBar(reason ?? '체크인 불가'); return; }
        final isAvailable = await NfcService.instance.isAvailable();
        if (!isAvailable) { _showSnackBar('NFC를 사용할 수 없습니다'); return; }
        if (!mounted) return;
        await showDialog(
            context: context,
            builder: (_) => _ChainCheckInDialog(
                chain: chain,
                nfcTags: ref.read(nfcTagProvider).tags,
                onSkip: (indices) async {
                    final tags = ref.read(nfcTagProvider).tags;
                    for (final i in indices) {
                        await ref.read(chainProvider.notifier).skipStep(chain, i, tags);
                    }
                },
            ),
        );
    }

    void _showSnackBar(String message) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message), duration: const Duration(seconds: 2)));
    }

    // ─── 빌드 ─────────────────────────────────────────────────────────────────

    @override
    Widget build(BuildContext context) {
        final alarms = ref.watch(alarmProvider).alarms;
        final chains = ref.watch(chainProvider).chains;
        final tags   = ref.watch(nfcTagProvider).tags;

        return Scaffold(
            backgroundColor: AppColors.background,
            drawer: _buildDrawer(tags),
            appBar: AppBar(
                backgroundColor: Colors.transparent,
                title: const Text('NFC 알람',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                iconTheme: const IconThemeData(color: Colors.white),
            ),
            body: _loading
                ? const Center(child: CircularProgressIndicator())
                : Column(children: [
                    if (!_overlayGranted) _buildOverlayWarning(),
                    Expanded(child: _buildMainList(alarms, chains, tags)),
                ]),
            floatingActionButton: FloatingActionButton(
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const AlarmEditScreen())),
                backgroundColor: AppColors.primary,
                child: const Icon(Icons.add, color: Colors.white),
            ),
        );
    }

    Widget _buildDrawer(nfcTags) {
        return Drawer(
            backgroundColor: AppColors.drawerBg,
            child: ListView(padding: EdgeInsets.zero, children: [
                const DrawerHeader(
                    decoration: BoxDecoration(color: AppColors.drawerHeader),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                            Icon(Icons.alarm, color: Colors.white, size: 40),
                            SizedBox(height: 10),
                            Text('NFC 알람', style: TextStyle(
                                color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                        ],
                    ),
                ),
                ListTile(
                    leading: const Icon(Icons.link, color: Colors.white70),
                    title: const Text('알람 체인 관리', style: TextStyle(color: Colors.white)),
                    onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const ChainEditScreen()));
                    },
                ),
                ListTile(
                    leading: const Icon(Icons.nfc, color: Colors.white70),
                    title: const Text('NFC 태그 관리', style: TextStyle(color: Colors.white)),
                    trailing: nfcTags.isEmpty ? const Badge(label: Text('!')) : null,
                    onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const NfcTagListScreen()));
                    },
                ),
                const Divider(color: Colors.white12),
                ListTile(
                    leading: const Icon(Icons.science_outlined, color: Colors.grey, size: 20),
                    title: const Text('5초 후 알람 테스트',
                        style: TextStyle(color: Colors.grey, fontSize: 13)),
                    onTap: () async {
                        Navigator.pop(context);
                        await AndroidAlarmManager.oneShotAt(
                            DateTime.now().add(const Duration(seconds: 5)),
                            AppConstants.testAlarmId, alarmFiredCallback,
                            alarmClock: true, exact: true, wakeup: true,
                        );
                        _showSnackBar('5초 후 알람 테스트');
                    },
                ),
            ]),
        );
    }

    Widget _buildOverlayWarning() {
        return GestureDetector(
            onTap: _requestOverlayPermission,
            child: Container(
                margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.orange.withValues(alpha: 0.6)),
                ),
                child: const Row(children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 18),
                    SizedBox(width: 8),
                    Expanded(child: Text('다른 앱 위에 표시 권한 없음 — 탭하여 허용',
                        style: TextStyle(color: Colors.orange, fontSize: 12))),
                ]),
            ),
        );
    }

    Widget _buildMainList(alarms, chains, tags) {
        final hasContent = chains.isNotEmpty || alarms.isNotEmpty;
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
                if (chains.isNotEmpty) ...[
                    Row(children: [
                        const Icon(Icons.link, color: Colors.white38, size: 14),
                        const SizedBox(width: 6),
                        const Text('알람 체인', style: TextStyle(color: Colors.white38, fontSize: 12)),
                        const Spacer(),
                        TextButton(
                            onPressed: () => Navigator.push(context,
                                MaterialPageRoute(builder: (_) => const ChainEditScreen())),
                            style: TextButton.styleFrom(
                                padding: EdgeInsets.zero, minimumSize: Size.zero),
                            child: const Text('+ 새 체인',
                                style: TextStyle(color: Colors.white38, fontSize: 11)),
                        ),
                    ]),
                    const SizedBox(height: 8),
                    ...chains.map((chain) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: ChainCard(
                            chain: chain,
                            nfcTags: tags,
                            countdown: _countdownForChain(chain),
                            checkInStatus: _checkInStatus(chain),
                            onTap: () => Navigator.push(context, MaterialPageRoute(
                                builder: (_) => ChainEditScreen(chain: chain))),
                            onCheckIn: () => _startChainCheckIn(chain),
                        ),
                    )),
                    if (alarms.isNotEmpty) const SizedBox(height: 8),
                ],
                if (alarms.isNotEmpty) ...[
                    if (chains.isNotEmpty)
                        const Padding(
                            padding: EdgeInsets.only(bottom: 8),
                            child: Row(children: [
                                Icon(Icons.alarm, color: Colors.white38, size: 14),
                                SizedBox(width: 6),
                                Text('개별 알람',
                                    style: TextStyle(color: Colors.white38, fontSize: 12)),
                            ]),
                        ),
                    ...alarms.map((alarm) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: AlarmListItem(
                            alarm: alarm,
                            countdownText: _countdownFor(alarm),
                            nfcTagName: _nfcTagNamesFor(alarm),
                            onTap: () => Navigator.push(context, MaterialPageRoute(
                                builder: (_) => AlarmEditScreen(alarm: alarm))),
                            onToggle: (v) {
                                final tags = ref.read(nfcTagProvider).tags;
                                ref.read(alarmProvider.notifier).toggle(alarm, v, tags);
                            },
                        ),
                    )),
                ],
            ],
        );
    }
}

// ─── 체인 체크인 다이얼로그 ───────────────────────────────────────────────────
class _ChainCheckInDialog extends StatefulWidget {
    final AlarmChain chain;
    final List nfcTags;
    final Future<void> Function(List<int>) onSkip;

    const _ChainCheckInDialog({
        required this.chain, required this.nfcTags, required this.onSkip});

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
        NfcService.instance.startSession(onDiscovered: (tag) async {
            final uid = NfcService.instance.extractUid(tag);
            await NfcService.instance.stopSession();
            if (uid == null || !mounted) return;

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
                appLog(LogTag.chain,
                    '체인 체크인 실패 — uid: $uid, 체인: "${widget.chain.name}" (유효하지 않은 태그)');
                setState(() {
                    _status = 'error';
                    _errorMsg = '체인의 2단계 이후 태그가 아닙니다\n1단계 태그는 체크인에 사용할 수 없습니다';
                });
                return;
            }
            appLog(LogTag.chain,
                '체인 체크인 스캔 성공 — uid: $uid, 체인: "${widget.chain.name}", 건너뜀 $scannedStep단계');
            setState(() {
                _toSkipIndices = List.generate(scannedStep!, (i) => i);
                _status = 'confirm';
            });
        });
    }

    @override
    void dispose() { NfcService.instance.stopSession(); super.dispose(); }

    @override
    Widget build(BuildContext context) {
        return AlertDialog(
            backgroundColor: AppColors.surface,
            title: Text('"${widget.chain.name}" 체크인',
                style: const TextStyle(color: Colors.white)),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
                const SizedBox(height: 8),
                if (_status == 'scanning') ...[
                    const CircularProgressIndicator(),
                    const SizedBox(height: 20),
                    const Text('태그를 폰에 갖다 대세요',
                        style: TextStyle(color: Colors.white70, fontSize: 15)),
                    const SizedBox(height: 4),
                    const Text('(2단계 이후 단계의 태그)',
                        style: TextStyle(color: Colors.white38, fontSize: 12)),
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
                    const Text('건너뜀 완료', style: TextStyle(
                        color: Colors.green, fontSize: 16, fontWeight: FontWeight.bold)),
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
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('취소')),
                    FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                        onPressed: () async {
                            appLog(LogTag.chain,
                                '체인 체크인 확정 — 체인: "${widget.chain.name}", 건너뜀 단계 수: ${_toSkipIndices.length}');
                            await widget.onSkip(_toSkipIndices);
                            if (mounted) setState(() => _status = 'done');
                        },
                        child: Text('${_toSkipIndices.length}개 건너뜀'),
                    ),
                ] else if (_status == 'error') ...[
                    TextButton(onPressed: _startScan, child: const Text('다시 시도')),
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('닫기')),
                ] else
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(_status == 'done' ? '완료' : '취소'),
                    ),
            ],
        );
    }
}
