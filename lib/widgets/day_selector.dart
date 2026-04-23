import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_constants.dart';

// ─── 요일 선택 위젯 (알람·체인 편집 화면 공용) ─────────────────────────────────
class DaySelector extends StatelessWidget {
    final List<int> selectedDays;
    final ValueChanged<List<int>> onChanged;

    const DaySelector({
        super.key,
        required this.selectedDays,
        required this.onChanged,
    });

    @override
    Widget build(BuildContext context) {
        return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(7, (i) {
                final day = i + 1;
                final selected = selectedDays.contains(day);
                return FilterChip(
                    label: Text(AppConstants.dayLabels[i]),
                    selected: selected,
                    onSelected: (v) {
                        final updated = List<int>.from(selectedDays);
                        if (v) {
                            updated.add(day);
                            updated.sort();
                        } else {
                            updated.remove(day);
                        }
                        onChanged(updated);
                    },
                    selectedColor: AppColors.primary,
                    checkmarkColor: Colors.white,
                    labelStyle: TextStyle(color: selected ? Colors.white : Colors.grey),
                    backgroundColor: AppColors.background,
                    side: BorderSide(color: selected ? Colors.blue : Colors.grey),
                );
            }),
        );
    }
}
