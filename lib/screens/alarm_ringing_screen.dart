import 'dart:async';
import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/app_colors.dart';
import '../constants/app_constants.dart';
import '../providers/alarm_ringing_provider.dart';
import '../providers/nfc_tag_provider.dart';
import '../services/app_logger.dart';
import '../services/nfc_service.dart';

// ─── 알람 울림 화면 ───────────────────────────────────────────────────────────
class AlarmRingingScreen extends ConsumerStatefulWidget {
    final VoidCallback onDismiss;
    const AlarmRingingScreen({super.key, required this.onDismiss});

    @override
    ConsumerState<AlarmRingingScreen> createState() => _AlarmRingingScreenState();
}

class _AlarmRingingScreenState extends ConsumerState<AlarmRingingScreen>
    with TickerProviderStateMixin {
    bool _isScanning = false;
    String _message = '다른 방으로 이동해서\nNFC 태그를 스캔하세요!';
    late AnimationController _pulseController;
    late Animation<double> _pulseAnimation;
    int _autoOffRemaining = AppConstants.autoOffSeconds;
    bool _isMuted = false;
    int _muteRemaining = 0;
    Timer? _ticker;

    void _onServiceData(Object data) {
        if (data.toString() == 'alarm_auto_off' && mounted) {
            widget.onDismiss();
            Navigator.of(context).pop();
        }
    }

    @override
    void initState() {
        super.initState();
        FlutterForegroundTask.addTaskDataCallback(_onServiceData);
        _pulseController = AnimationController(
            vsync: this, duration: const Duration(seconds: 1))
          ..repeat(reverse: true);
        _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
            CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));
        _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
            if (!mounted) return;
            setState(() {
                if (_autoOffRemaining > 0) _autoOffRemaining--;
                if (_isMuted && _muteRemaining > 0) {
                    _muteRemaining--;
                    if (_muteRemaining == 0) {
                        _isMuted = false;
                        FlutterForegroundTask.sendDataToTask('resume_sound');
                    }
                }
            });
        });
        _checkNfcStatus();
    }

    Future<void> _checkNfcStatus() async {
        final isAvailable = await NfcService.instance.isAvailable();
        if (!isAvailable && mounted) {
            showDialog(
                context: context,
                barrierDismissible: false,
                builder: (ctx) => AlertDialog(
                    title: const Text('NFC가 꺼져 있습니다'),
                    content: const Text(
                        '알람을 끄려면 NFC가 필요합니다.\nNFC 설정을 열어 활성화하세요.'),
                    actions: [
                        TextButton(
                            onPressed: () async {
                                Navigator.of(ctx).pop();
                                const AndroidIntent(
                                    action: 'android.settings.NFC_SETTINGS').launch();
                            },
                            child: const Text('NFC 설정 열기')),
                    ],
                ),
            );
        }
    }

    @override
    void dispose() {
        FlutterForegroundTask.removeTaskDataCallback(_onServiceData);
        _ticker?.cancel();
        _pulseController.dispose();
        NfcService.instance.stopSession();
        super.dispose();
    }

    void _cancelScan() {
        NfcService.instance.stopSession();
        setState(() {
            _isScanning = false;
            _message = '다른 방으로 이동해서\nNFC 태그를 스캔하세요!';
        });
    }

    void _toggleMute() {
        if (_isMuted) {
            setState(() { _isMuted = false; _muteRemaining = 0; });
            FlutterForegroundTask.sendDataToTask('resume_sound');
        } else {
            setState(() { _isMuted = true; _muteRemaining = AppConstants.muteDurationSeconds; });
            FlutterForegroundTask.sendDataToTask('mute_temporary');
        }
    }

    Future<void> _startScan() async {
        setState(() { _isScanning = true; _message = '태그에 갖다 대세요...'; });

        final activeUids = ref.read(alarmRingingProvider).activeNfcUids;
        final allTags   = ref.read(nfcTagProvider).tags;

        NfcService.instance.startSession(onDiscovered: (tag) async {
            final uid = NfcService.instance.extractUid(tag);
            NfcService.instance.stopSession();

            bool success;
            if (activeUids.isNotEmpty) {
                success = activeUids.contains(uid);
            } else {
                success = allTags.any((t) => t.uid == uid);
            }
            appLog(LogTag.nfc, 'NFC 스캔 결과 — uid: $uid, 성공: $success');

            if (success) {
                widget.onDismiss();
                if (mounted) {
                    setState(() => _message = '기상 성공!');
                    Future.delayed(const Duration(milliseconds: 800), () {
                        if (mounted) Navigator.of(context).pop();
                    });
                }
            } else {
                if (mounted) {
                    setState(() {
                        _isScanning = false;
                        _message = '잘못된 태그입니다!\n다시 시도하세요';
                    });
                }
            }
        });
    }

    String get _autoOffText {
        final m = _autoOffRemaining ~/ 60;
        final s = (_autoOffRemaining % 60).toString().padLeft(2, '0');
        return '$m:$s 후 자동 꺼짐';
    }

    String get _muteButtonText {
        if (!_isMuted) return '잠깐만 조용히 (2분)';
        final m = _muteRemaining ~/ 60;
        final s = (_muteRemaining % 60).toString().padLeft(2, '0');
        return '$m:$s 후 소리 재시작 — 탭하여 지금 재시작';
    }

    @override
    Widget build(BuildContext context) {
        return PopScope(
            canPop: false,
            child: Scaffold(
                backgroundColor: AppColors.ringing,
                body: SafeArea(
                    child: Center(child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                            ScaleTransition(
                                scale: _pulseAnimation,
                                child: const Icon(Icons.alarm, size: 120, color: Colors.red)),
                            const SizedBox(height: 24),
                            const Text('알람!', style: TextStyle(
                                color: Colors.red, fontSize: 40, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 12),
                            Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 40),
                                child: Text(_message, textAlign: TextAlign.center,
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 20, height: 1.5))),
                            const SizedBox(height: 8),
                            Text(_autoOffText,
                                style: const TextStyle(color: Colors.white38, fontSize: 12)),
                            const SizedBox(height: 32),
                            GestureDetector(
                                onTap: _isScanning ? null : _startScan,
                                child: Container(
                                    width: 160, height: 160,
                                    decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: _isScanning
                                            ? Colors.grey.withValues(alpha: 0.3)
                                            : Colors.red.withValues(alpha: 0.2),
                                        border: Border.all(
                                            color: _isScanning ? Colors.grey : Colors.red,
                                            width: 3),
                                    ),
                                    child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                            _isScanning
                                                ? const CircularProgressIndicator(
                                                    color: Colors.white)
                                                : const Icon(Icons.nfc,
                                                    size: 64, color: Colors.red),
                                            const SizedBox(height: 8),
                                            Text(_isScanning ? '스캔 중...' : '탭해서 스캔',
                                                style: const TextStyle(
                                                    color: Colors.white, fontSize: 14)),
                                        ],
                                    ),
                                ),
                            ),
                            const SizedBox(height: 16),
                            if (_isScanning)
                                TextButton.icon(
                                    onPressed: _cancelScan,
                                    icon: const Icon(Icons.close,
                                        size: 16, color: Colors.white38),
                                    label: const Text('스캔 취소',
                                        style: TextStyle(color: Colors.white38, fontSize: 13)))
                            else
                                const SizedBox(height: 32),
                            TextButton(
                                onPressed: _toggleMute,
                                child: Text(_muteButtonText, style: TextStyle(
                                    color: _isMuted ? Colors.orange : Colors.white54,
                                    fontSize: 13))),
                        ],
                    )),
                ),
            ),
        );
    }
}
