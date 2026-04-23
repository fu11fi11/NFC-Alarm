import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

// ─── 알람 소리 선택 위젯 (알람·단계 편집 화면 공용) ───────────────────────────
class SoundSelector extends StatelessWidget {
    final String selectedSound;
    final ValueChanged<String> onChanged;

    const SoundSelector({
        super.key,
        required this.selectedSound,
        required this.onChanged,
    });

    @override
    Widget build(BuildContext context) {
        return SegmentedButton<String>(
            style: SegmentedButton.styleFrom(
                backgroundColor: AppColors.surface,
                selectedBackgroundColor: AppColors.primary,
                foregroundColor: Colors.grey,
                selectedForegroundColor: Colors.white,
            ),
            segments: const [
                ButtonSegment(value: 'alarm',        label: Text('알람'),   icon: Icon(Icons.alarm, size: 16)),
                ButtonSegment(value: 'notification', label: Text('알림'),   icon: Icon(Icons.notifications, size: 16)),
                ButtonSegment(value: 'ringtone',     label: Text('벨소리'), icon: Icon(Icons.music_note, size: 16)),
                ButtonSegment(value: 'silent',       label: Text('무음'),   icon: Icon(Icons.volume_off, size: 16)),
            ],
            selected: {selectedSound},
            onSelectionChanged: (s) => onChanged(s.first),
        );
    }
}
