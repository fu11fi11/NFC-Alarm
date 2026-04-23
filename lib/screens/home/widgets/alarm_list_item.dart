import 'package:flutter/material.dart';
import '../../../constants/app_colors.dart';
import '../../../constants/app_constants.dart';
import '../../../models/alarm_data.dart';

// ─── 알람 목록 아이템 ─────────────────────────────────────────────────────────
class AlarmListItem extends StatelessWidget {
    final AlarmData alarm;
    final String countdownText;
    final String nfcTagName;
    final VoidCallback onTap;
    final ValueChanged<bool> onToggle;

    const AlarmListItem({
        super.key,
        required this.alarm,
        required this.countdownText,
        required this.nfcTagName,
        required this.onTap,
        required this.onToggle,
    });

    static const _soundIcons = {
        'alarm':        Icons.alarm,
        'notification': Icons.notifications,
        'ringtone':     Icons.music_note,
        'silent':       Icons.volume_off,
    };

    @override
    Widget build(BuildContext context) {
        final h = alarm.hour.toString().padLeft(2, '0');
        final m = alarm.minute.toString().padLeft(2, '0');
        final daysText = alarm.days.isEmpty
            ? '반복 없음'
            : alarm.days.map((d) => AppConstants.dayLabels[d - 1]).join(' ');

        return GestureDetector(
            onTap: onTap,
            child: Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
                decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white12),
                ),
                child: Row(children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('$h:$m', style: TextStyle(
                            color: alarm.enabled ? Colors.white : Colors.grey,
                            fontSize: 40, fontWeight: FontWeight.bold, letterSpacing: 2,
                        )),
                        const SizedBox(height: 4),
                        Text(daysText, style: TextStyle(
                            color: alarm.enabled ? Colors.white70 : Colors.grey, fontSize: 13)),
                        const SizedBox(height: 4),
                        Row(children: [
                            Icon(Icons.nfc, size: 12,
                                color: alarm.nfcTagIds.isNotEmpty
                                    ? Colors.lightBlueAccent : Colors.grey),
                            const SizedBox(width: 3),
                            Text(nfcTagName, style: TextStyle(
                                color: alarm.nfcTagIds.isNotEmpty
                                    ? Colors.lightBlueAccent : Colors.grey,
                                fontSize: 11)),
                            const SizedBox(width: 10),
                            Icon(_soundIcons[alarm.soundType] ?? Icons.alarm,
                                size: 12, color: Colors.grey),
                            const SizedBox(width: 3),
                            Text('${(alarm.volume * 100).round()}%',
                                style: const TextStyle(color: Colors.grey, fontSize: 11)),
                            if (countdownText.isNotEmpty) ...[
                                const SizedBox(width: 10),
                                Text(countdownText,
                                    style: const TextStyle(color: Colors.white38, fontSize: 11)),
                            ],
                        ]),
                    ])),
                    Switch(value: alarm.enabled, onChanged: onToggle, activeThumbColor: Colors.green),
                ]),
            ),
        );
    }
}
