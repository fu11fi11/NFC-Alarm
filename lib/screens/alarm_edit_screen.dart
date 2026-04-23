import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/app_colors.dart';
import '../models/alarm_data.dart';
import '../providers/alarm_provider.dart';
import '../providers/nfc_tag_provider.dart';
import '../services/app_logger.dart';
import '../widgets/day_selector.dart';
import '../widgets/sound_selector.dart';

// ─── 알람 편집 / 생성 화면 ────────────────────────────────────────────────────
class AlarmEditScreen extends ConsumerStatefulWidget {
    final AlarmData? alarm;
    const AlarmEditScreen({super.key, this.alarm});

    @override
    ConsumerState<AlarmEditScreen> createState() => _AlarmEditScreenState();
}

class _AlarmEditScreenState extends ConsumerState<AlarmEditScreen> {
    late int _hour, _minute;
    late List<int> _days, _nfcTagIds;
    late String _soundType;
    late double _volume;
    bool _saving = false;

    @override
    void initState() {
        super.initState();
        if (widget.alarm != null) {
            _hour = widget.alarm!.hour;
            _minute = widget.alarm!.minute;
            _days = List.from(widget.alarm!.days);
            _nfcTagIds = List.from(widget.alarm!.nfcTagIds);
            _soundType = widget.alarm!.soundType;
            _volume = widget.alarm!.volume;
        } else {
            final now = TimeOfDay.now();
            _hour = now.hour;
            _minute = now.minute;
            _days = [1, 2, 3, 4, 5];
            _nfcTagIds = [];
            _soundType = 'alarm';
            _volume = 1.0;
        }
    }

    Future<void> _pickTime() async {
        final picked = await showTimePicker(
            context: context,
            initialTime: TimeOfDay(hour: _hour, minute: _minute),
        );
        if (picked != null) {
            setState(() { _hour = picked.hour; _minute = picked.minute; });
        }
    }

    Future<void> _save() async {
        if (_days.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('요일을 하나 이상 선택하세요'),
                    duration: Duration(seconds: 2)));
            return;
        }
        setState(() => _saving = true);
        final tags = ref.read(nfcTagProvider).tags;
        if (widget.alarm == null) {
            appLog(LogTag.alarm,
                '알람 생성 — 시간: ${_hour.toString().padLeft(2, '0')}:${_minute.toString().padLeft(2, '0')}');
            await ref.read(alarmProvider.notifier).add(
                hour: _hour, minute: _minute, days: _days,
                nfcTagIds: _nfcTagIds, soundType: _soundType,
                volume: _volume, allTags: tags,
            );
        } else {
            appLog(LogTag.alarm,
                '알람 수정 — ID: ${widget.alarm!.id}, 시간: ${_hour.toString().padLeft(2, '0')}:${_minute.toString().padLeft(2, '0')}');
            await ref.read(alarmProvider.notifier).update(
                widget.alarm!,
                hour: _hour, minute: _minute, days: _days,
                nfcTagIds: _nfcTagIds, soundType: _soundType,
                volume: _volume, allTags: tags,
            );
        }
        if (mounted) Navigator.pop(context);
    }

    Future<void> _confirmDelete() async {
        final confirm = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
                title: const Text('알람 삭제'),
                content: const Text('이 알람을 삭제할까요?'),
                actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('취소')),
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('삭제', style: TextStyle(color: Colors.red))),
                ],
            ),
        );
        if (confirm == true) {
            appLog(LogTag.alarm, '알람 삭제 — ID: ${widget.alarm!.id}');
            final tags = ref.read(nfcTagProvider).tags;
            await ref.read(alarmProvider.notifier).delete(widget.alarm!, tags);
            if (mounted) Navigator.pop(context);
        }
    }

    @override
    Widget build(BuildContext context) {
        final nfcTags = ref.watch(nfcTagProvider).tags;
        final h = _hour.toString().padLeft(2, '0');
        final m = _minute.toString().padLeft(2, '0');

        return Scaffold(
            backgroundColor: AppColors.background,
            appBar: AppBar(
                backgroundColor: Colors.transparent,
                title: Text(widget.alarm == null ? '새 알람' : '알람 편집',
                    style: const TextStyle(color: Colors.white)),
                iconTheme: const IconThemeData(color: Colors.white),
                actions: [
                    if (widget.alarm != null)
                        IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                            onPressed: _confirmDelete),
                ],
            ),
            body: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    GestureDetector(
                        onTap: _pickTime,
                        child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 28),
                            decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.white12),
                            ),
                            child: Center(child: Text('$h:$m', style: const TextStyle(
                                color: Colors.white, fontSize: 72,
                                fontWeight: FontWeight.bold, letterSpacing: 4))),
                        ),
                    ),
                    const SizedBox(height: 6),
                    const Center(child: Text('탭하여 시간 변경',
                        style: TextStyle(color: Colors.grey, fontSize: 12))),
                    const SizedBox(height: 28),
                    const Text('반복 요일', style: TextStyle(color: Colors.grey, fontSize: 13)),
                    const SizedBox(height: 12),
                    DaySelector(
                        selectedDays: _days,
                        onChanged: (days) => setState(() => _days = days),
                    ),
                    const SizedBox(height: 28),
                    const Text('알람 소리', style: TextStyle(color: Colors.grey, fontSize: 13)),
                    const SizedBox(height: 12),
                    SoundSelector(
                        selectedSound: _soundType,
                        onChanged: (s) => setState(() => _soundType = s),
                    ),
                    const SizedBox(height: 28),
                    Row(children: [
                        const Text('볼륨', style: TextStyle(color: Colors.grey, fontSize: 13)),
                        const Spacer(),
                        Text('${(_volume * 100).round()}%',
                            style: const TextStyle(color: Colors.white, fontSize: 13)),
                    ]),
                    Slider(
                        value: _volume, min: 0.1, max: 1.0, divisions: 9,
                        activeColor: AppColors.primary,
                        onChanged: _soundType == 'silent'
                            ? null
                            : (v) => setState(() => _volume = v),
                    ),
                    const SizedBox(height: 28),
                    const Text('NFC 태그 (알람 해제용 — 하나라도 태그되면 해제)',
                        style: TextStyle(color: Colors.grey, fontSize: 13)),
                    const SizedBox(height: 12),
                    if (nfcTags.isEmpty)
                        const Text(
                            '등록된 NFC 태그가 없습니다. 메뉴 > NFC 태그 관리에서 먼저 등록하세요.',
                            style: TextStyle(color: Colors.orange, fontSize: 11))
                    else
                        Wrap(spacing: 8, runSpacing: 8, children: [
                            FilterChip(
                                label: const Text('아무 태그나'),
                                selected: _nfcTagIds.isEmpty,
                                onSelected: (v) {
                                    if (v) setState(() => _nfcTagIds.clear());
                                },
                                selectedColor: AppColors.primary,
                                checkmarkColor: Colors.white,
                                labelStyle: TextStyle(
                                    color: _nfcTagIds.isEmpty ? Colors.white : Colors.grey),
                                backgroundColor: AppColors.background,
                                side: BorderSide(
                                    color: _nfcTagIds.isEmpty ? Colors.blue : Colors.grey),
                            ),
                            ...nfcTags.map((t) {
                                final sel = _nfcTagIds.contains(t.id);
                                return FilterChip(
                                    label: Text(t.name),
                                    selected: sel,
                                    onSelected: (v) => setState(() {
                                        if (v) { _nfcTagIds.add(t.id); }
                                        else { _nfcTagIds.remove(t.id); }
                                    }),
                                    selectedColor: AppColors.primary,
                                    checkmarkColor: Colors.white,
                                    labelStyle: TextStyle(
                                        color: sel ? Colors.white : Colors.grey),
                                    backgroundColor: AppColors.background,
                                    side: BorderSide(
                                        color: sel ? Colors.blue : Colors.grey),
                                );
                            }),
                        ]),
                    const SizedBox(height: 100),
                ]),
            ),
            floatingActionButton: FloatingActionButton.extended(
                onPressed: _saving ? null : _save,
                backgroundColor: AppColors.primary,
                icon: _saving
                    ? const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.check, color: Colors.white),
                label: const Text('저장', style: TextStyle(color: Colors.white)),
            ),
        );
    }
}
