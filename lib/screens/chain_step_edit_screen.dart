import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../models/chain_step.dart';
import '../models/nfc_tag_data.dart';
import '../widgets/sound_selector.dart';

// ─── 체인 단계 편집 화면 ──────────────────────────────────────────────────────
class ChainStepEditScreen extends StatefulWidget {
    final ChainStep? step;
    final List<NfcTagData> nfcTags;
    final Set<int> excludedTagIds;

    const ChainStepEditScreen({
        super.key,
        required this.step,
        required this.nfcTags,
        this.excludedTagIds = const {},
    });

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
            _hour = widget.step!.hour;
            _minute = widget.step!.minute;
            _labelCtrl = TextEditingController(text: widget.step!.label);
            _nfcTagIds = List.from(widget.step!.nfcTagIds);
            _soundType = widget.step!.soundType;
            _volume = widget.step!.volume;
        } else {
            final now = TimeOfDay.now();
            _hour = now.hour;
            _minute = now.minute;
            _labelCtrl = TextEditingController();
            _nfcTagIds = [];
            _soundType = 'alarm';
            _volume = 1.0;
        }
    }

    @override
    void dispose() { _labelCtrl.dispose(); super.dispose(); }

    Future<void> _pickTime() async {
        final picked = await showTimePicker(
            context: context,
            initialTime: TimeOfDay(hour: _hour, minute: _minute),
        );
        if (picked != null) {
            setState(() { _hour = picked.hour; _minute = picked.minute; });
        }
    }

    void _save() {
        Navigator.pop(context, ChainStep(
            hour: _hour, minute: _minute,
            label: _labelCtrl.text.trim(),
            nfcTagIds: _nfcTagIds,
            soundType: _soundType,
            volume: _volume,
        ));
    }

    @override
    Widget build(BuildContext context) {
        final h = _hour.toString().padLeft(2, '0');
        final m = _minute.toString().padLeft(2, '0');

        return Scaffold(
            backgroundColor: AppColors.background,
            appBar: AppBar(
                backgroundColor: Colors.transparent,
                title: Text(widget.step == null ? '새 단계' : '단계 편집',
                    style: const TextStyle(color: Colors.white)),
                iconTheme: const IconThemeData(color: Colors.white),
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
                    const SizedBox(height: 24),
                    TextField(
                        controller: _labelCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                            labelText: '단계 이름 (선택, 예: 기상, 헬스장)',
                            labelStyle: const TextStyle(color: Colors.grey),
                            enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Colors.white24)),
                            focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Colors.blue)),
                        ),
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
                    const Text('NFC 태그 (하나라도 태그되면 해제)',
                        style: TextStyle(color: Colors.grey, fontSize: 13)),
                    const SizedBox(height: 12),
                    if (widget.nfcTags.isEmpty)
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
                            ...widget.nfcTags.map((t) {
                                final sel = _nfcTagIds.contains(t.id);
                                final excluded = widget.excludedTagIds.contains(t.id);
                                return FilterChip(
                                    label: Text(excluded ? '${t.name} (사용 중)' : t.name),
                                    selected: sel,
                                    onSelected: excluded
                                        ? null
                                        : (v) => setState(() {
                                            if (v) { _nfcTagIds.add(t.id); }
                                            else { _nfcTagIds.remove(t.id); }
                                        }),
                                    selectedColor: AppColors.primary,
                                    checkmarkColor: Colors.white,
                                    labelStyle: TextStyle(color: excluded
                                        ? Colors.grey.shade700
                                        : sel ? Colors.white : Colors.grey),
                                    backgroundColor: AppColors.background,
                                    side: BorderSide(color: excluded
                                        ? Colors.grey.shade800
                                        : sel ? Colors.blue : Colors.grey),
                                );
                            }),
                        ]),
                    const SizedBox(height: 100),
                ]),
            ),
            floatingActionButton: FloatingActionButton.extended(
                onPressed: _save,
                backgroundColor: AppColors.primary,
                icon: const Icon(Icons.check, color: Colors.white),
                label: const Text('저장', style: TextStyle(color: Colors.white)),
            ),
        );
    }
}
